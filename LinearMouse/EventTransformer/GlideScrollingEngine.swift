// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: THE ANIMATION MATH
//
// Part of Glide scrolling. Overview: Documentation/Glide.md
//
// This file only does math. It never touches events, timers or the screen,
// which keeps it easy to unit test (see GlideScrollingTests.swift).
//
// Contents
//   1. GlideCurve           The easing curve: how far along a glide is at a
//                           given moment (fast start, soft stop).
//   2. GlideScrollingAxis   One axis (vertical or horizontal). Keeps a target
//                           position, moves it on every wheel click, and works
//                           out how many pixels to scroll on each screen frame.
//   3. GlideScrollingEngine Two axes side by side, so vertical and horizontal
//                           glides run independently.
//   4. Settings conversion  Turns the user's configuration into axis settings.

import Foundation

// MARK: - 1. GlideCurve

/// Easing curve used by glide scrolling.
///
/// `value(at:)` takes how far through the glide's time we are (0 = just
/// started, 1 = finished) and returns how far through the glide's distance
/// the page should be (also 0 ... 1).
///
/// One formula covers every curve the user can pick:
///
///     f(s) = 1 - (1 - s)^3 * (1 + (3 - a) * s),   s in 0 ... 1
///
/// - `f(0) = 0` and `f(1) = 1`: starts at the start, ends exactly at the end.
/// - At `s = 1` both speed and acceleration are zero, so the page settles
///   gently and never coasts past its target.
/// - `a` is the starting speed (the slope at `s = 0`): 4 is easeOutQuart,
///   3 is easeOutCubic, 2 is a gentler ease-out, 0 starts from standstill.
/// - For every `a` in `0 ... 4` the curve only ever moves forward. That is
///   what lets a new click restart the curve at the page's current speed
///   without overshooting (see `GlideScrollingAxis.add`).
struct GlideCurve: Equatable {
    /// Starting speeds the formula supports without overshooting.
    static let initialSlopeRange: ClosedRange<Double> = 0 ... 4

    /// `a` in the formula above.
    let initialSlope: Double

    init(initialSlope: Double) {
        self.initialSlope = initialSlope.clamped(to: Self.initialSlopeRange)
    }

    /// Fraction of the distance covered after fraction `progress` of the time.
    func value(at progress: Double) -> Double {
        let s = progress.clamped(to: 0 ... 1)
        let remaining = 1 - s
        return 1 - remaining * remaining * remaining * (1 + (3 - initialSlope) * s)
    }

    /// The curve's speed at `progress` (its derivative, d f / d s). Used to
    /// carry the page's current speed into the next glide when a new wheel
    /// click arrives.
    func slope(at progress: Double) -> Double {
        let s = progress.clamped(to: 0 ... 1)
        let remaining = 1 - s
        return remaining * remaining * (initialSlope + 4 * (3 - initialSlope) * s)
    }
}

// MARK: - 2. GlideScrollingAxis

/// Destination-based scroll animation for one axis.
///
/// The idea, the same one Chromium uses for mouse wheels:
/// - Each wheel click moves a *target* further along.
/// - The page glides from where it is now to that target over a fixed time,
///   following `GlideCurve`, and stops exactly on it.
/// - A click that arrives mid-glide extends the target and keeps the current
///   speed, so clicks join into one smooth movement instead of stacking up.
///
/// Positions are in pixels on a private ruler that restarts at zero each time
/// the axis comes to rest. `emitted` is the exact (fractional) distance
/// already sent to apps, so the total sent for a glide is exactly its target.
///
/// Timing follows the display's frames:
/// - A glide that starts from rest is placed so that its first frame shows
///   exactly one frame's worth of movement.
/// - A click that arrives between two frames is treated as if it arrived on
///   the last frame shown. Every frame then gets an even, full-length step,
///   even while clicks keep arriving.
struct GlideScrollingAxis {
    struct Settings: Equatable {
        /// Pixels moved by one wheel click (lines × line height).
        var pixelsPerDetent: Double
        /// Seconds from the latest click until the glide stops.
        var duration: TimeInterval
        /// Starting speed of the curve for a glide from rest (`a` in
        /// `GlideCurve`).
        var initialSlope: Double
    }

    /// Shortest glide segment allowed when very fast clicking shortens it.
    private static let minimumSegmentDuration: TimeInterval = 1.0 / 120.0
    /// When a click arrives mid-glide the new segment normally starts at the
    /// page's current speed. This floor (a quarter of the curve's own
    /// starting speed) keeps a click near the very end of a glide responsive.
    private static let minimumRetargetSlopeFraction = 0.25

    let settings: Settings

    /// Whether a glide is in progress.
    private(set) var isActive = false
    /// Where the current glide will stop, in pixels.
    private(set) var target = 0.0
    /// Where the current segment started, in pixels.
    private var origin = 0.0
    /// Exact distance already sent to apps for this glide.
    private var emitted = 0.0
    /// Time of the last frame we produced movement for.
    private var lastSampleTime: TimeInterval = 0
    /// Set when a glide starts from rest. Its start time is decided on the
    /// first frame (in `advance`), so that frame shows exactly one frame of
    /// movement no matter when, between frames, the click arrived.
    private var startsOnNextFrame = false
    /// When the current segment started.
    private var startTime: TimeInterval = 0
    /// How long the current segment lasts.
    private var segmentDuration: TimeInterval = 0
    /// The curve for the current segment (its starting speed can differ from
    /// the user's choice when a click arrives mid-glide).
    private var curve: GlideCurve

    init(settings: Settings) {
        self.settings = settings
        curve = GlideCurve(initialSlope: settings.initialSlope)
    }

    /// Where the page should be at `time`, in pixels.
    func position(at time: TimeInterval) -> Double {
        guard isActive else {
            return emitted
        }
        return origin + (target - origin) * curve.value(at: progress(at: time))
    }

    /// How fast the page is moving at `time`, in pixels per second.
    func velocity(at time: TimeInterval) -> Double {
        guard isActive, segmentDuration > 0 else {
            return 0
        }
        let s = progress(at: time)
        guard s < 1 else {
            return 0
        }
        // The curve's slope is "fraction of distance per fraction of time";
        // multiply by the distance and divide by the time to get pixels/second.
        return (target - origin) * curve.slope(at: s) / segmentDuration
    }

    /// Handles wheel clicks: moves the target by `detents` clicks and starts a
    /// new glide segment from the current position, carrying the current
    /// speed. `detents` is negative for the opposite direction.
    mutating func add(detents: Int, at time: TimeInterval) {
        let distance = Double(detents) * settings.pixelsPerDetent
        guard distance != 0, distance.isFinite else {
            return
        }

        var time = time
        if isActive {
            // Mid-glide: act as if the click arrived on the last frame shown,
            // so the next frame gets a normal, full-length step.
            if !startsOnNextFrame {
                time = lastSampleTime
            }
        } else {
            // At rest: reset the private ruler to zero.
            origin = 0
            emitted = 0
            target = 0
        }

        let current = position(at: time)
        var speed = velocity(at: time)
        // Which way the page is heading (by speed, or by remaining distance
        // if it has not started moving yet).
        let movingDirection = speed != 0 ? speed : target - current

        if movingDirection != 0, movingDirection.sign != distance.sign {
            // The user reversed direction: drop the unfinished distance and
            // head the other way, starting from standstill.
            target = current + distance
            speed = 0
        } else {
            // Same direction (or at rest): push the destination further.
            target += distance
        }

        let delta = target - current
        // Less than half a pixel to go: nothing worth animating.
        guard abs(delta) >= 0.5 else {
            isActive = false
            return
        }

        var duration = settings.duration
        var slope = settings.initialSlope.clamped(to: GlideCurve.initialSlopeRange)

        // Keep the current speed, as Chromium does. The new segment starts
        // with slope = speed × duration / distance, which is exactly the
        // page's current speed, so nothing jumps when a click arrives.
        // A small floor keeps a click in the slow tail of a glide responsive.
        // The curve cannot start faster than slope 4 without overshooting, so
        // if that would be needed, shorten the segment instead.
        if speed != 0 {
            let carriedSlope = speed * duration / delta
            slope = max(carriedSlope, slope * Self.minimumRetargetSlopeFraction)
            if slope > GlideCurve.initialSlopeRange.upperBound {
                slope = GlideCurve.initialSlopeRange.upperBound
                duration = max(slope * delta / speed, Self.minimumSegmentDuration)
            }
        }

        if !isActive {
            // From rest: the real start time is fixed on the first frame.
            startsOnNextFrame = true
        }
        origin = current
        startTime = time
        lastSampleTime = time
        segmentDuration = duration
        curve = GlideCurve(initialSlope: slope)
        isActive = true
    }

    /// Called once per screen frame. Moves the glide to the frame shown at
    /// `time` and returns the exact distance (in pixels, may be fractional)
    /// to scroll for that frame. `frameInterval` is one frame at the
    /// display's full refresh rate.
    mutating func advance(to time: TimeInterval, frameInterval: TimeInterval = 1.0 / 60.0) -> Double {
        guard isActive else {
            return 0
        }

        if startsOnNextFrame {
            // First frame of a glide from rest: start the glide one frame
            // earlier, so this frame shows exactly one frame of movement.
            startsOnNextFrame = false
            startTime = time - frameInterval
            lastSampleTime = startTime
        }

        // Never go back in time: a late or repeated frame time moves nothing.
        let time = max(time, lastSampleTime)
        lastSampleTime = time
        let finished = progress(at: time) >= 1
        // On the last frame, land exactly on the target (no rounding drift).
        let position = finished ? target : position(at: time)
        let delta = position - emitted
        emitted = position

        if finished {
            isActive = false
        }

        return delta
    }

    /// Cancels the glide immediately, for example when switching apps or when
    /// a game captures the mouse.
    mutating func stop() {
        isActive = false
        origin = 0
        target = 0
        emitted = 0
        lastSampleTime = 0
        startsOnNextFrame = false
    }

    /// Fraction of the current segment's time that has passed (0 ... 1).
    private func progress(at time: TimeInterval) -> Double {
        if startsOnNextFrame {
            // Not started yet: the first frame decides the start time.
            return 0
        }
        guard segmentDuration > 0 else {
            return 1
        }
        return ((time - startTime) / segmentDuration).clamped(to: 0 ... 1)
    }
}

// MARK: - 3. GlideScrollingEngine

/// Two independent glide axes. An axis is `nil` when glide scrolling is off
/// for that direction, which means "leave that direction alone".
struct GlideScrollingEngine {
    enum Axis {
        case horizontal
        case vertical
    }

    private(set) var horizontal: GlideScrollingAxis?
    private(set) var vertical: GlideScrollingAxis?

    init(horizontal: GlideScrollingAxis.Settings?, vertical: GlideScrollingAxis.Settings?) {
        self.horizontal = horizontal.map(GlideScrollingAxis.init(settings:))
        self.vertical = vertical.map(GlideScrollingAxis.init(settings:))
    }

    /// Whether either axis is still gliding (the frame clock keeps running
    /// while this is true).
    var isRunning: Bool {
        horizontal?.isActive == true || vertical?.isActive == true
    }

    /// Whether glide scrolling is on for `axis`.
    func handles(_ axis: Axis) -> Bool {
        switch axis {
        case .horizontal:
            return horizontal != nil
        case .vertical:
            return vertical != nil
        }
    }

    /// Passes wheel clicks to one axis. See `GlideScrollingAxis.add`.
    mutating func add(detents: Int, on axis: Axis, at time: TimeInterval) {
        switch axis {
        case .horizontal:
            horizontal?.add(detents: detents, at: time)
        case .vertical:
            vertical?.add(detents: detents, at: time)
        }
    }

    /// Exact distances to scroll on both axes for one screen frame.
    mutating func advance(
        to time: TimeInterval,
        frameInterval: TimeInterval = 1.0 / 60.0
    ) -> (deltaX: Double, deltaY: Double) {
        (
            horizontal?.advance(to: time, frameInterval: frameInterval) ?? 0,
            vertical?.advance(to: time, frameInterval: frameInterval) ?? 0
        )
    }

    /// Cancels both axes.
    mutating func stop() {
        horizontal?.stop()
        vertical?.stop()
    }

    /// Cancels one axis.
    mutating func stop(_ axis: Axis) {
        switch axis {
        case .horizontal:
            horizontal?.stop()
        case .vertical:
            vertical?.stop()
        }
    }
}

// MARK: - 4. Settings conversion

extension GlideScrollingAxis.Settings {
    /// Builds axis settings from the user's `scrolling.glide` configuration.
    init(_ glide: Scheme.Scrolling.Glide) {
        self.init(
            pixelsPerDetent: glide.pixelsPerDetent,
            duration: glide.resolvedDuration,
            initialSlope: glide.resolvedCurve.initialSlope
        )
    }
}
