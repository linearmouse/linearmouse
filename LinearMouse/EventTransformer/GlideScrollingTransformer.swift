// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: THE EVENT TRANSFORMER
//
// Part of Glide scrolling. Overview: Documentation/Glide.md
//
// This is where Glide plugs into LinearMouse's event pipeline. It sits in
// the same place as SmoothedScrollingTransformer and is added by
// EventTransformerManager only for axes where `scrolling.glide` is on.
//
// What it does with each scroll wheel event:
//   - Mouse wheel click  -> swallow it and add one click to the glide.
//   - Wheel click while a game has captured the mouse (cursor hidden)
//                        -> pass it on as one plain wheel click instead.
//   - Trackpad / Magic Mouse / anything already smooth -> leave it alone.
// Then, once per screen frame, it posts a small, plain scroll event with
// that frame's share of the glide.
//
// Contents
//   1. Setup              Settings, dependencies (injectable for tests), state.
//   2. transform(_:in:)   Handles each incoming scroll wheel event.
//   3. tick               Runs once per screen frame and posts the movement.
//   4. Input              Counts physical wheel clicks.
//   5. Output             Builds and posts the scroll events.
//   6. Frame clock        Starts and stops the per-frame callback.

import Foundation
import os.log

// MARK: - 1. Setup

/// Turns notched mouse wheel clicks into a short, destination-based glide.
///
/// - Each click moves a target by a fixed pixel distance (see
///   `GlideScrollingEngine`).
/// - Once per screen refresh (see `GlideDisplayFrameClock`) it posts a plain
///   continuous pixel scroll event: no scroll phase, no momentum phase, no
///   companion gesture events. Apps therefore treat it as simple precise
///   scrolling and do not add momentum or "trackpad" behaviour of their own.
/// - Continuous input (trackpads, Magic Mouse) passes through untouched.
/// - While a game has captured the mouse (the cursor is hidden), axes with
///   game detection on skip the glide and pass one plain wheel click per
///   notch, so games still see one step per click.
final class GlideScrollingTransformer: EventTransformer, Deactivatable {
    /// Glide only cares about scroll events, so pointer movement skips it.
    var handlesPointerMotion: Bool {
        false
    }

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GlideScrolling")

    /// The user's glide settings per axis (`nil` = glide off for that axis).
    private let glide: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Glide>

    /// Dependencies. The defaults are the real implementations; unit tests
    /// pass fakes (a fixed clock, a list instead of posting, a fake cursor
    /// check, a manual frame clock).
    /// Tells whether this device has a high-resolution wheel, and how many
    /// fine steps it sends per notch.
    private let highResolutionWheelMultiplier: (EventTransformerContext) -> Int?
    /// Current time.
    private let now: () -> TimeInterval
    /// Posts a finished scroll event.
    private let eventSink: (CGEvent) -> Void
    /// Whether the cursor is hidden (a game has captured the mouse).
    private let isCursorHidden: () -> Bool
    /// Creates the per-frame clock.
    private let makeFrameClock: (@escaping (TimeInterval) -> Void) -> GlideFrameClocking

    /// The animation math for both axes.
    private var engine: GlideScrollingEngine
    /// Created on the first glide.
    private var frameClock: GlideFrameClocking?
    /// Some apps (Chromium) only read whole pixels. The fractions left over
    /// from each frame are kept here and added to the next one, so those apps
    /// still receive the full distance.
    private var pointRemainderX = 0.0
    private var pointRemainderY = 0.0
    /// Modifier keys held during the last wheel click, copied onto the
    /// glide's events (so for example Cmd+scroll still zooms).
    private var lastFlags: CGEventFlags = []
    /// Turn a high-resolution wheel's fine steps back into whole notches.
    private var verticalHighResolutionCounter = LogitechHighResolutionWheelScrollCounter()
    private var horizontalHighResolutionCounter = LogitechHighResolutionWheelScrollCounter()

    init(
        glide: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Glide>,
        highResolutionWheelMultiplier: @escaping (EventTransformerContext) -> Int? = {
            $0.device?.highResolutionWheelNormalizationMultiplier
        },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
        isCursorHidden: @escaping () -> Bool = GlideCursorCapture.isCursorHidden,
        makeFrameClock: @escaping (@escaping (TimeInterval) -> Void) -> GlideFrameClocking = {
            GlideDisplayFrameClock(handler: $0)
        }
    ) {
        self.glide = glide
        self.highResolutionWheelMultiplier = highResolutionWheelMultiplier
        self.now = now
        self.eventSink = eventSink
        self.isCursorHidden = isCursorHidden
        self.makeFrameClock = makeFrameClock
        engine = Self.makeEngine(glide)
    }

    private static func makeEngine(
        _ glide: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Glide>
    ) -> GlideScrollingEngine {
        GlideScrollingEngine(
            horizontal: glide.horizontal.map { GlideScrollingAxis.Settings($0) },
            vertical: glide.vertical.map { GlideScrollingAxis.Settings($0) }
        )
    }

    // MARK: - 2. transform(_:in:)

    /// Called by LinearMouse for every input event. Returns the event to pass
    /// on, a modified event, or `nil` to swallow it.
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        // Our own glide events come back through the pipeline; let them pass.
        if event.isLinearMouseSyntheticEvent {
            return event
        }

        let view = ScrollWheelEventView(event)

        // Only notched (discrete) wheel input glides. Trackpads, Magic Mouse
        // and other continuous or phased input already scroll smoothly.
        guard !view.continuous, view.scrollPhase == nil, view.momentumPhase == .none else {
            return event
        }

        // Which axes of this event Glide takes over.
        let interceptsX = engine.handles(.horizontal) && view.deltaXSignum != 0
        let interceptsY = engine.handles(.vertical) && view.deltaYSignum != 0

        guard interceptsX || interceptsY else {
            return event
        }

        lastFlags = event.flags
        let timestamp = now()

        // Game detection. Ask about the cursor only when an axis that would
        // glide has game detection on (the check is cheap, but not needed
        // otherwise). If the cursor is hidden, that axis sends one plain
        // wheel click instead of gliding.
        let checksCursor = (interceptsX && glide.horizontal?.detectsGames == true)
            || (interceptsY && glide.vertical?.detectsGames == true)
        let cursorHidden = checksCursor && isCursorHidden()
        let discreteX = interceptsX && cursorHidden && glide.horizontal?.detectsGames == true
        let discreteY = interceptsY && cursorHidden && glide.vertical?.detectsGames == true

        // Keep the event if it still carries an axis Glide does not handle.
        var keepsEvent = (!interceptsX && view.deltaXSignum != 0) || (!interceptsY && view.deltaYSignum != 0)

        if interceptsX {
            let detents = horizontalDetents(from: view, in: context) ?? 0
            if discreteX {
                // Game mode: cancel any glide and send one clean click.
                engine.stop(.horizontal)
                keepsEvent = Self.setDiscreteHorizontal(detents, on: view) || keepsEvent
            } else {
                // Glide mode: add the click to the glide and remove this axis
                // from the original event.
                if detents != 0 {
                    engine.add(detents: detents, on: .horizontal, at: timestamp)
                }
                Self.zeroHorizontal(on: view)
            }
        }

        if interceptsY {
            let detents = verticalDetents(from: view, in: context) ?? 0
            if discreteY {
                engine.stop(.vertical)
                keepsEvent = Self.setDiscreteVertical(detents, on: view) || keepsEvent
            } else {
                if detents != 0 {
                    engine.add(detents: detents, on: .vertical, at: timestamp)
                }
                Self.zeroVertical(on: view)
            }
        }

        // Frames are only needed while something is gliding.
        if engine.isRunning {
            startClockIfNeeded()
        } else {
            stopClock()
        }

        return keepsEvent ? event : nil
    }

    /// Called when LinearMouse switches to another app's or device's settings.
    /// Cancels any glide in progress.
    func deactivate() {
        stopClock()
        engine.stop()
        lastFlags = []
        verticalHighResolutionCounter = LogitechHighResolutionWheelScrollCounter()
        horizontalHighResolutionCounter = LogitechHighResolutionWheelScrollCounter()
    }

    // MARK: - 3. tick

    /// Advances one frame using the current time. Used by unit tests.
    func tick() {
        tick(at: now())
    }

    /// Called by the frame clock once per screen frame. Works out this
    /// frame's movement and posts it.
    func tick(at frameTime: TimeInterval) {
        let frameInterval = frameClock?.frameInterval ?? 1.0 / 60.0
        let (deltaX, deltaY) = engine.advance(to: frameTime, frameInterval: frameInterval)
        let finished = !engine.isRunning

        // On the last frame, send any leftover pixel fractions too.
        post(deltaX: deltaX, deltaY: deltaY, flushRemainders: finished)

        if finished {
            stopClock()
        }
    }

    // MARK: - 4. Input

    /// Number of physical wheel notches in this event. One plain wheel event
    /// counts as one notch, exactly like line mode, so macOS wheel
    /// acceleration does not change the glide distance. High-resolution
    /// wheels send many fine steps per notch; those are added up into notches.
    private func verticalDetents(from view: ScrollWheelEventView, in context: EventTransformerContext) -> Int? {
        guard let multiplier = highResolutionWheelMultiplier(context), multiplier > 1 else {
            return Int(view.deltaYSignum)
        }

        return verticalHighResolutionCounter.consume(
            units: LogitechHighResolutionWheelUnitReader.verticalUnitResolution(
                from: view,
                multiplier: multiplier
            )
            .rawUnits,
            multiplier: multiplier,
            now: now()
        )
    }

    /// Horizontal version of `verticalDetents`.
    private func horizontalDetents(from view: ScrollWheelEventView, in context: EventTransformerContext) -> Int? {
        guard let multiplier = highResolutionWheelMultiplier(context), multiplier > 1 else {
            return Int(view.deltaXSignum)
        }

        return horizontalHighResolutionCounter.consume(
            units: LogitechHighResolutionWheelUnitReader.horizontalUnitResolution(
                from: view,
                multiplier: multiplier
            )
            .rawUnits,
            multiplier: multiplier,
            now: now()
        )
    }

    // MARK: - 5. Output

    /// Posts one frame of movement as a plain continuous scroll event.
    /// A scroll event carries the distance in several fields, and different
    /// apps read different ones:
    /// - the fixed-point field gets the exact amount, including fractions of
    ///   a pixel (read by AppKit apps and Safari, for smooth endings);
    /// - the point field gets whole pixels, with the leftover fraction carried
    ///   to the next frame (read by Chromium-based apps).
    private func post(deltaX: Double, deltaY: Double, flushRemainders: Bool) {
        let pointsX = Self.wholePoints(deltaX, remainder: &pointRemainderX, flush: flushRemainders)
        let pointsY = Self.wholePoints(deltaY, remainder: &pointRemainderY, flush: flushRemainders)

        // Nothing worth sending this frame.
        let minimumDelta = 0.001
        guard abs(deltaX) >= minimumDelta || abs(deltaY) >= minimumDelta || pointsX != 0 || pointsY != 0 else {
            return
        }

        let pixelsX = Int32(pointsX.clamped(to: Double(Int32.min) ... Double(Int32.max)))
        let pixelsY = Int32(pointsY.clamped(to: Double(Int32.min) ... Double(Int32.max)))

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: pixelsY,
            wheel2: pixelsX,
            wheel3: 0
        ) else {
            return
        }

        // Plain continuous scroll: no scroll phase and no momentum phase, so
        // apps do not treat it as a trackpad gesture or add their own coasting.
        let view = ScrollWheelEventView(event)
        view.continuous = true
        view.scrollPhase = nil
        view.momentumPhase = .none
        view.deltaXPt = Double(pixelsX)
        view.deltaXFixedPt = deltaX
        view.ioHidScrollX = deltaX
        view.deltaYPt = Double(pixelsY)
        view.deltaYFixedPt = deltaY
        view.ioHidScrollY = deltaY

        // Mark it as ours so the pipeline does not process it again, and
        // keep the modifier keys from the original click.
        event.isLinearMouseSyntheticEvent = true
        event.flags = lastFlags
        eventSink(event)

        os_log(
            "post glide scroll deltaX=%{public}.3f deltaY=%{public}.3f",
            log: Self.log,
            type: .debug,
            deltaX,
            deltaY
        )
    }

    /// Whole pixels to send this frame. The fraction left over is kept in
    /// `remainder` for the next frame; on the last frame (`flush`) it is
    /// rounded and sent so nothing is lost.
    private static func wholePoints(_ delta: Double, remainder: inout Double, flush: Bool) -> Double {
        let combined = delta + remainder
        let points = flush ? combined.rounded() : combined.rounded(.towardZero)
        remainder = flush ? 0 : combined - points
        return points
    }

    /// Game mode: rewrites the axis as exactly one plain wheel click per notch
    /// (like line mode with 1 line), so wheel acceleration cannot turn one
    /// click into several game steps. Returns whether there is anything to
    /// send.
    private static func setDiscreteHorizontal(_ detents: Int, on view: ScrollWheelEventView) -> Bool {
        guard detents != 0 else {
            zeroHorizontal(on: view)
            return false
        }
        view.continuous = false
        // Set every distance field, as LogitechHighResolutionWheelNormalizer
        // does, so apps reading any of them see exactly one click per notch.
        view.deltaX = Int64(detents)
        view.deltaXPt = Double(detents) * 10
        view.deltaXFixedPt = Double(detents)
        view.ioHidScrollX = Double(detents)
        return true
    }

    /// Vertical version of `setDiscreteHorizontal`.
    private static func setDiscreteVertical(_ detents: Int, on view: ScrollWheelEventView) -> Bool {
        guard detents != 0 else {
            zeroVertical(on: view)
            return false
        }
        view.continuous = false
        view.deltaY = Int64(detents)
        view.deltaYPt = Double(detents) * 10
        view.deltaYFixedPt = Double(detents)
        view.ioHidScrollY = Double(detents)
        return true
    }

    /// Removes horizontal scrolling from an event (all of its distance fields).
    private static func zeroHorizontal(on view: ScrollWheelEventView) {
        view.deltaX = 0
        view.deltaXPt = 0
        view.deltaXFixedPt = 0
        view.ioHidScrollX = 0
    }

    /// Removes vertical scrolling from an event (all of its distance fields).
    private static func zeroVertical(on view: ScrollWheelEventView) {
        view.deltaY = 0
        view.deltaYPt = 0
        view.deltaYFixedPt = 0
        view.ioHidScrollY = 0
    }

    // MARK: - 6. Frame clock

    private func startClockIfNeeded() {
        if frameClock == nil {
            // Weak reference: the clock must not keep this transformer alive.
            frameClock = makeFrameClock { [weak self] frameTime in
                self?.tick(at: frameTime)
            }
        }
        frameClock?.start()
    }

    private func stopClock() {
        frameClock?.stop()
        pointRemainderX = 0
        pointRemainderY = 0
    }
}
