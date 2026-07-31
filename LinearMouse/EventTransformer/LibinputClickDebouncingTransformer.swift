// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

final class LibinputClickDebouncingTransformer: EventTransformer, DeferredEventTransformer, Deactivatable {
    static let bounceTimeout: TimeInterval = 0.025
    static let spuriousTimeout: TimeInterval = 0.012
    private static let bounceTimeoutNanoseconds: UInt64 = 25_000_000
    private static let spuriousTimeoutNanoseconds: UInt64 = 12_000_000

    final class TimerToken {
        private var invalidateHandler: (() -> Void)?

        init(invalidate: @escaping () -> Void) {
            invalidateHandler = invalidate
        }

        deinit {
            invalidate()
        }

        func invalidate() {
            invalidateHandler?()
            invalidateHandler = nil
        }
    }

    typealias TimerScheduler = (TimeInterval, @escaping () -> Void) -> TimerToken?
    typealias MonotonicClock = () -> UInt64

    private struct DeferredEvent {
        var event: CGEvent
        var sink: (CGEvent) -> Void
    }

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "LibinputClickDebouncing"
    )

    private let button: CGMouseButton
    private let scheduleTimer: TimerScheduler
    private let monotonicClock: MonotonicClock
    private let fallbackEventSink: (CGEvent) -> Void

    private var engine = LibinputClickDebouncingEngine()
    private var bounceTimer: TimerToken?
    private var spuriousTimer: TimerToken?
    // RunLoop timers are wakeups only. These monotonic deadlines define the
    // actual state-machine boundary when a wakeup is delayed.
    private var bounceDeadline: UInt64?
    private var spuriousDeadline: UInt64?
    private var bounceTimerGeneration: UInt64 = 0
    private var spuriousTimerGeneration: UInt64 = 0
    private var pendingPress: DeferredEvent?
    private var pendingRelease: DeferredEvent?

    init(
        for button: CGMouseButton,
        scheduleTimer: @escaping TimerScheduler = LibinputClickDebouncingTransformer.scheduleEventThreadTimer,
        monotonicClock: @escaping MonotonicClock = { DispatchTime.now().uptimeNanoseconds },
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    ) {
        self.button = button
        self.scheduleTimer = scheduleTimer
        self.monotonicClock = monotonicClock
        fallbackEventSink = eventSink
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard let inputState = buttonState(of: event),
              let eventButton = MouseEventView(event).mouseButton else {
            return event
        }

        expireElapsedTimers(at: monotonicClock())

        guard eventButton == button else {
            _ = process(.otherButton)
            return event
        }

        let deferredEvent = DeferredEvent(
            event: event.copy() ?? event,
            sink: context.deferredEventSink ?? fallbackEventSink
        )
        switch inputState {
        case .pressed:
            pendingPress = deferredEvent
        case .released:
            pendingRelease = deferredEvent
        }

        let forwardsCurrentEvent = process(
            inputState == .pressed ? .press : .release,
            currentEventState: inputState
        )
        return forwardsCurrentEvent ? event : nil
    }

    func deactivate() {
        // Flushing through OTHERBUTTON mirrors libinput's neutral-state
        // guarantee and balances any press or release held by a timer.
        _ = process(.otherButton)
        cancelBounceTimer()
        cancelSpuriousTimer()
        engine = LibinputClickDebouncingEngine()
        pendingPress = nil
        pendingRelease = nil
    }

    private static func scheduleEventThreadTimer(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> TimerToken? {
        guard let timer = EventThread.shared.scheduleTimer(
            interval: interval,
            repeats: false,
            handler: handler
        ) else {
            return nil
        }

        return TimerToken {
            timer.invalidate()
        }
    }

    private func buttonState(of event: CGEvent) -> LibinputClickDebouncingEngine.ButtonState? {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return .pressed
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return .released
        default:
            return nil
        }
    }

    @discardableResult
    private func process(
        _ input: LibinputClickDebouncingEngine.Input,
        currentEventState: LibinputClickDebouncingEngine.ButtonState? = nil
    ) -> Bool {
        let previousState = engine.state
        let effects = engine.handle(input)
        var forwardsCurrentEvent = false

        for effect in effects {
            switch effect {
            case let .emit(buttonState):
                if buttonState == currentEventState {
                    forwardsCurrentEvent = true
                } else {
                    emitPendingEvent(for: buttonState)
                }
                clearPendingEvent(for: buttonState)
            case .setBounceTimer:
                setBounceTimer()
            case .setSpuriousTimer:
                setSpuriousTimer()
            case .cancelBounceTimer:
                cancelBounceTimer()
            case .cancelSpuriousTimer:
                cancelSpuriousTimer()
            case .spuriousDebouncingEnabled:
                os_log(
                    "Enabled short release debouncing for button %{public}u",
                    log: Self.log,
                    type: .info,
                    button.rawValue
                )
            }
        }

        discardUnusedPendingEvents()

        os_log(
            "Button %{public}u: %{public}@ -> %{public}@ -> %{public}@",
            log: Self.log,
            type: .debug,
            button.rawValue,
            String(describing: previousState),
            String(describing: input),
            String(describing: engine.state)
        )

        return forwardsCurrentEvent
    }

    private func emitPendingEvent(for state: LibinputClickDebouncingEngine.ButtonState) {
        let deferredEvent: DeferredEvent?
        switch state {
        case .pressed:
            deferredEvent = pendingPress
        case .released:
            deferredEvent = pendingRelease
        }

        guard let deferredEvent else {
            os_log(
                "Cannot emit %{public}@ for button %{public}u: no pending event",
                log: Self.log,
                type: .error,
                String(describing: state),
                button.rawValue
            )
            return
        }
        deferredEvent.sink(deferredEvent.event)
    }

    private func clearPendingEvent(for state: LibinputClickDebouncingEngine.ButtonState) {
        switch state {
        case .pressed:
            pendingPress = nil
        case .released:
            pendingRelease = nil
        }
    }

    private func discardUnusedPendingEvents() {
        switch engine.state {
        case .isUpDelaying, .isUpDelayingSpurious:
            pendingPress = nil
        case .isDownDetectingSpurious, .isDownDelaying:
            pendingRelease = nil
        case .isUp, .isDown, .isDownWaiting, .isUpDetectingSpurious, .isUpWaiting:
            pendingPress = nil
            pendingRelease = nil
        }
    }

    private func setBounceTimer() {
        cancelBounceTimer()
        bounceTimerGeneration &+= 1
        let generation = bounceTimerGeneration
        let deadline = monotonicClock() &+ Self.bounceTimeoutNanoseconds
        bounceDeadline = deadline
        scheduleBounceTimer(deadline: deadline, generation: generation)
    }

    private func scheduleBounceTimer(deadline: UInt64, generation: UInt64) {
        let interval = interval(until: deadline)
        bounceTimer = scheduleTimer(interval) { [weak self] in
            guard let self else {
                return
            }
            handleBounceTimer(generation: generation)
        }

        if bounceTimer == nil {
            fireBounceTimeout()
        }
    }

    private func setSpuriousTimer() {
        cancelSpuriousTimer()
        spuriousTimerGeneration &+= 1
        let generation = spuriousTimerGeneration
        let deadline = monotonicClock() &+ Self.spuriousTimeoutNanoseconds
        spuriousDeadline = deadline
        scheduleSpuriousTimer(deadline: deadline, generation: generation)
    }

    private func scheduleSpuriousTimer(deadline: UInt64, generation: UInt64) {
        let interval = interval(until: deadline)
        spuriousTimer = scheduleTimer(interval) { [weak self] in
            guard let self else {
                return
            }
            handleSpuriousTimer(generation: generation)
        }

        if spuriousTimer == nil {
            fireSpuriousTimeout()
        }
    }

    private func cancelBounceTimer() {
        bounceTimerGeneration &+= 1
        bounceTimer?.invalidate()
        bounceTimer = nil
        bounceDeadline = nil
    }

    private func cancelSpuriousTimer() {
        spuriousTimerGeneration &+= 1
        spuriousTimer?.invalidate()
        spuriousTimer = nil
        spuriousDeadline = nil
    }

    private func handleBounceTimer(generation: UInt64) {
        guard generation == bounceTimerGeneration,
              let deadline = bounceDeadline else {
            return
        }

        let now = monotonicClock()
        if now < deadline {
            scheduleBounceTimer(deadline: deadline, generation: generation)
        } else {
            expireElapsedTimers(at: now)
        }
    }

    private func handleSpuriousTimer(generation: UInt64) {
        guard generation == spuriousTimerGeneration,
              let deadline = spuriousDeadline else {
            return
        }

        let now = monotonicClock()
        if now < deadline {
            scheduleSpuriousTimer(deadline: deadline, generation: generation)
        } else {
            expireElapsedTimers(at: now)
        }
    }

    private func expireElapsedTimers(at now: UInt64) {
        while true {
            let bounceIsNext = switch (bounceDeadline, spuriousDeadline) {
            case let (bounce?, spurious?):
                bounce <= spurious
            case (.some, .none):
                true
            case (.none, .some), (.none, .none):
                false
            }

            if bounceIsNext, let deadline = bounceDeadline, deadline <= now {
                fireBounceTimeout()
            } else if let deadline = spuriousDeadline, deadline <= now {
                fireSpuriousTimeout()
            } else {
                return
            }
        }
    }

    private func fireBounceTimeout() {
        bounceTimerGeneration &+= 1
        bounceTimer?.invalidate()
        bounceTimer = nil
        bounceDeadline = nil
        process(.bounceTimeout)
    }

    private func fireSpuriousTimeout() {
        spuriousTimerGeneration &+= 1
        spuriousTimer?.invalidate()
        spuriousTimer = nil
        spuriousDeadline = nil
        process(.spuriousTimeout)
    }

    private func interval(until deadline: UInt64) -> TimeInterval {
        let now = monotonicClock()
        guard deadline > now else {
            return 0
        }
        return TimeInterval(deadline - now) / 1_000_000_000
    }
}
