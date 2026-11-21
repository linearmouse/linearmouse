// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import GestureKit
import os.log

/// One device's interactive swipe between spaces, fed by `SpaceSwipeTransformer`.
///
/// Wheels report coarse steps at irregular intervals, while the Dock animates
/// smoothly only when fed a steady stream of small updates, as a trackpad
/// does. So wheel input only moves a target; a display-rate animation eases
/// the swipe toward it and is what the Dock actually sees.
///
/// The session belongs to the device rather than to a route: switching spaces
/// changes the app under the pointer, and therefore the route, mid-swipe. It
/// releases itself on a timer, so it never holds a route interaction lease
/// and never pins mouse buttons to a route.
final class SpaceSwipeSession {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "SpaceSwipe")

    /// The Dock follows at most one space per gesture. Past this, finish the
    /// current swipe and begin the next one so a long spin keeps moving.
    private static let chainThreshold = 1.0
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
    private var releaseDelay: TimeInterval = 0
    private var lastInputTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    private var frameTimer: EventThreadTimer?
    private var resendTimers: [EventThreadTimer] = []

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping Scheduler = { EventThread.shared.scheduleTimer(interval: $0, repeats: $1, handler: $2) },
        sink: @escaping (Output) -> Void
    ) {
        self.now = now
        self.schedule = schedule
        self.sink = sink
    }

    var isActive: Bool {
        state != .idle
    }

    // MARK: - Input

    /// Moves the swipe target by `delta` spaces. The swipe is released once no
    /// input has arrived for `releaseDelay` and the animation has settled.
    func move(by delta: Double, releaseDelay: TimeInterval) {
        guard delta != 0, delta.isFinite else {
            return
        }

        lastInputTime = now()
        self.releaseDelay = releaseDelay
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

    /// Abandons the swipe, snapping the space back, and drops pending end
    /// event resends so they cannot reach the Dock during a later swipe.
    func cancel() {
        stopFrames()
        if state == .swiping {
            finish(phase: .cancelled)
        } else {
            cancelResends()
        }
        state = .idle
        target = 0
        progress = 0
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
        guard state != .idle else {
            stopFrames()
            return
        }

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
                // Settled: the last easing step is not a fling, so the Dock
                // decides by position alone.
                velocity = 0
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

    /// A swipe is only released once the animation has settled, so the Dock
    /// decides by position: past halfway it switches, otherwise it snaps back.
    private func finish(phase: CGSGesturePhase) {
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

extension SpaceSwipeSession.Output {
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
