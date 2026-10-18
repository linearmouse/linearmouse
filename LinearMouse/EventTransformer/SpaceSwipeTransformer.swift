// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import GestureKit
import os.log

/// Drives the Dock's interactive space-switching swipe from horizontal wheel
/// movement, so the space follows the wheel like a trackpad swipe and snaps
/// to the nearest space once the wheel stops.
///
/// Wheels report coarse steps at irregular intervals, while the Dock animates
/// smoothly only when fed a steady stream of small updates, as a trackpad
/// does. So wheel input only moves a target; a display-rate animation eases
/// the swipe toward it and is what the Dock actually sees.
final class SpaceSwipeTransformer: EventTransformer, EventTransformerInteractionTracking, Deactivatable {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "SpaceSwipe")

    /// The Dock follows at most one space per gesture. Past this, finish the
    /// current swipe and begin the next one so a long spin keeps moving.
    private static let chainThreshold = 1.0
    /// Line-equivalent of continuous (pixel) horizontal scrolling.
    private static let pointsPerLine = 10.0
    /// Positive wheel deltas mean "left"; the Dock moves left on negative progress.
    private static let progressSign = -1.0
    /// A trackpad reports at about this rate; so does the follow animation.
    private static let frameInterval: TimeInterval = 1.0 / 120
    /// Time constant of the follow animation. Long enough to blend wheel
    /// steps into one motion, short enough to still feel attached to the wheel.
    private static let followTimeConstant: TimeInterval = 0.05
    /// The animation counts as caught up once it is this close to the target.
    private static let settleTolerance = 0.002
    /// The Dock drops end events while busy, which leaves the space stuck
    /// mid-swipe. Re-sending the same end event unsticks it.
    private static let endEventResendDelays: [TimeInterval] = [0.2, 0.5]

    /// One update of the Dock's swipe, in spaces.
    struct Output: Equatable {
        var phase: CGSGesturePhase
        var progress: Double
        var velocity: Double
    }

    private let distance: Double
    private let releaseDelay: TimeInterval
    typealias Scheduler = (_ interval: TimeInterval, _ repeats: Bool, _ handler: @escaping () -> Void)
        -> EventThreadTimer?

    private let sink: (Output) -> Void
    private let now: () -> TimeInterval
    private let schedule: Scheduler

    private enum State {
        case idle
        /// Input arrived; the first frame posts `.began`.
        case pending
        case swiping
    }

    private var state = State.idle
    /// Where the wheel says the swipe should be, in spaces.
    private var target = 0.0
    /// What the Dock has been told, in spaces.
    private var progress = 0.0
    private var postedProgress = 0.0
    private var velocity = 0.0
    private var lastInputTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    private var frameTimer: EventThreadTimer?
    private var resendTimers: [EventThreadTimer] = []

    init(
        distance: Double,
        releaseDelay: TimeInterval,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping Scheduler = { EventThread.shared.scheduleTimer(interval: $0, repeats: $1, handler: $2) },
        sink: @escaping (Output) -> Void
    ) {
        self.distance = distance
        self.releaseDelay = releaseDelay
        self.now = now
        self.schedule = schedule
        self.sink = sink
    }

    var handlesPointerMotion: Bool {
        false
    }

    var hasActiveInteraction: Bool {
        state != .idle
    }

    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel, !event.isLinearMouseSyntheticEvent else {
            return event
        }

        let view = ScrollWheelEventView(event)

        // Trackpads already swipe between spaces natively.
        if view.scrollPhase != nil || view.momentumPhase != .none {
            return event
        }

        guard let input = ScrollInput.read(from: view, highResolutionMultiplier: nil),
              input.axis == .horizontal
        else {
            return event
        }

        let steps = Self.steps(of: input, rawDelta: view.ioHidScrollX)
        move(by: Self.progressSign * steps / distance)
        return nil
    }

    func deactivate() {
        stopFrames()
        if state == .swiping {
            finish(phase: .cancelled)
        }
        state = .idle
        target = 0
        progress = 0
    }

    /// Prefer the device's raw value: the system accelerates horizontal lines,
    /// which turns a steady spin into uneven jumps. The selected delta still
    /// decides the direction, since it already reflects reversing.
    static func steps(of input: ScrollInput, rawDelta: Double) -> Double {
        let magnitude: Double
        if rawDelta.isFinite, rawDelta != 0 {
            magnitude = abs(rawDelta)
        } else if input.units == .points {
            magnitude = abs(input.delta) / pointsPerLine
        } else {
            magnitude = abs(input.delta)
        }
        return input.delta > 0 ? magnitude : -magnitude
    }

    // MARK: - Input

    private func move(by delta: Double) {
        guard delta != 0, delta.isFinite else {
            return
        }

        lastInputTime = now()
        if state == .idle {
            state = .pending
            target = 0
            progress = 0
            velocity = 0
            cancelResends()
        }
        target += delta
        startFrames()
    }

    // MARK: - Animation

    private func startFrames() {
        guard frameTimer == nil else {
            return
        }
        lastFrameTime = now()
        frameTimer = schedule(Self.frameInterval, true) { [weak self] in
            self?.frame()
        }
    }

    private func stopFrames() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    /// Advances the follow animation by one frame. Driven by a timer while active.
    func frame() {
        let time = now()
        let elapsed = min(max(time - lastFrameTime, 0), 0.1)
        lastFrameTime = time

        if elapsed > 0 {
            let follow = 1 - exp(-elapsed / Self.followTimeConstant)
            let step = (target - progress) * follow
            progress += step
            velocity = step / elapsed
        }

        if abs(target - progress) < Self.settleTolerance {
            progress = target
        }

        if state == .pending, progress != 0 {
            state = .swiping
            post(phase: .began)
            postedProgress = progress
        } else if state == .swiping, progress != postedProgress {
            post(phase: .changed)
            postedProgress = progress
        }

        if state == .swiping, abs(progress) >= Self.chainThreshold {
            chain()
            return
        }

        let inputIdle = time - lastInputTime >= releaseDelay
        if inputIdle, progress == target {
            stopFrames()
            if state == .swiping {
                finish(phase: .ended)
            }
            state = .idle
        }
    }

    /// Completes the current space and carries the rest of the target into a
    /// fresh swipe, as if the fingers were lifted and placed again mid-spin.
    private func chain() {
        let direction: Double = progress > 0 ? 1 : -1
        progress = Self.chainThreshold * direction
        finish(phase: .ended)
        target -= Self.chainThreshold * direction
        progress = 0
        state = .pending
    }

    // MARK: - Output

    private func finish(phase requestedPhase: CGSGesturePhase) {
        // Like lifting the fingers after reversing a trackpad swipe: moving
        // back toward the start while releasing abandons the switch.
        let reversing = velocity != 0 && velocity.sign != progress.sign
        let phase: CGSGesturePhase = requestedPhase == .ended && reversing ? .cancelled : requestedPhase
        let output = Output(phase: phase, progress: progress, velocity: velocity)
        sink(output)
        scheduleResends(of: output)
        os_log(
            "Space swipe %{public}@ at progress %{public}.2f, velocity %{public}.2f",
            log: Self.log,
            type: .debug,
            phase == .ended ? "ended" : "cancelled",
            progress,
            velocity
        )
    }

    private func scheduleResends(of output: Output) {
        cancelResends()
        resendTimers = Self.endEventResendDelays.compactMap { delay in
            schedule(delay, false) { [sink] in
                sink(output)
            }
        }
    }

    private func cancelResends() {
        resendTimers.forEach { $0.invalidate() }
        resendTimers = []
    }

    private func post(phase: CGSGesturePhase) {
        if phase == .began {
            cancelResends()
        }
        sink(Output(phase: phase, progress: progress, velocity: 0))
    }
}

extension SpaceSwipeTransformer.Output {
    var gestureEvent: GestureEvent? {
        GestureEvent(
            dockSwipeSource: nil,
            motion: .horizontal,
            phase: phase,
            progress: progress,
            velocity: velocity
        )
    }
}
