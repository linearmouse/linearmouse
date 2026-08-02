// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import KeyKit
import os.log

final class ButtonMappingTransformer: EventTransformer, DeferredEventTransformer {
    typealias Mapping = Scheme.Buttons.Mapping
    typealias TimerScheduler = (TimeInterval, @escaping () -> Void) -> TimerToken?
    typealias MonotonicClock = () -> UInt64

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

    private struct DeferredEvent {
        var event: CGEvent
        var sink: (CGEvent) -> Void
    }

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ButtonMapping"
    )

    private var engine: ButtonMappingEngine
    let mappings: [Mapping]
    let universalBackForward: Scheme.Buttons.UniversalBackForward?
    private let actionExecutor: ButtonActionExecutor
    private let scheduleTimer: TimerScheduler
    private let monotonicClock: MonotonicClock
    private let fallbackEventSink: (CGEvent) -> Void
    private let swapsPrimaryAndSecondaryButtons: Bool
    private let gestureTransformer: GestureButtonTransformer?

    private var timer: TimerToken?
    private var timerGeneration: UInt64 = 0
    private var scheduledDeadline: UInt64?
    private var bufferedEvents = [DeferredEvent]()
    private var targetBundleIdentifier: String?

    init(
        mappings: [Mapping],
        universalBackForward: Scheme.Buttons.UniversalBackForward? = nil,
        policy: ButtonMappingPolicy = .default,
        swapsPrimaryAndSecondaryButtons: Bool = false,
        scheduleTimer: @escaping TimerScheduler = ButtonMappingTransformer.scheduleEventThreadTimer,
        monotonicClock: @escaping MonotonicClock = { DispatchTime.now().uptimeNanoseconds },
        keySimulator: KeySimulating? = nil,
        gestureTransformer: GestureButtonTransformer? = nil,
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    ) {
        self.mappings = mappings
        self.universalBackForward = universalBackForward
        engine = .init(mappings: mappings, policy: policy)
        actionExecutor = .init(
            universalBackForward: universalBackForward,
            keySimulator: keySimulator
        )
        self.scheduleTimer = scheduleTimer
        self.monotonicClock = monotonicClock
        fallbackEventSink = eventSink
        self.swapsPrimaryAndSecondaryButtons = swapsPrimaryAndSecondaryButtons
        self.gestureTransformer = gestureTransformer
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard !SettingsState.shared.recording,
              !event.isLinearMouseSyntheticEvent else {
            return event
        }

        if let gestureTransformer,
           gestureTransformer.transform(event, in: context) == nil {
            return nil
        }

        if [.keyDown, .keyUp].contains(event.type) {
            if let flags = actionExecutor.keySimulator.modifiedCGEventFlags(of: event) {
                event.flags = flags
            }
            return event
        }

        let now = monotonicClock()
        process(engine.advance(to: now))

        if event.isGestureCleanupRelease,
           let button = mappingButton(of: event) {
            let cancellation = engine.cancelInteractions(containing: button)
            if cancellation.consumesEvent {
                bufferedEvents.removeAll()
                process(cancellation)
                scheduleNextDeadline()
                return nil
            }
        }

        if let targetBundleIdentifier = MouseEventView(event).targetPid?.bundleIdentifier {
            self.targetBundleIdentifier = targetBundleIdentifier
        }

        var output: ButtonMappingEngine.Output
        let canBuffer: Bool
        let alwaysForwardsEvent: Bool

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard let button = mappingButton(of: event) else {
                return event
            }
            output = engine.buttonDown(button, modifierFlags: event.flags, at: now)
            canBuffer = true
            alwaysForwardsEvent = false

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard let button = mappingButton(of: event) else {
                return event
            }
            output = engine.buttonUp(button, modifierFlags: event.flags, at: now)
            canBuffer = true
            alwaysForwardsEvent = false

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let button = mappingButton(of: event)
            output = engine.pointerMoved(
                for: button,
                deltaX: event.getDoubleValueField(.mouseEventDeltaX),
                deltaY: event.getDoubleValueField(.mouseEventDeltaY),
                at: now
            )
            canBuffer = true
            alwaysForwardsEvent = false

        case .mouseMoved:
            output = engine.pointerMoved(
                deltaX: event.getDoubleValueField(.mouseEventDeltaX),
                deltaY: event.getDoubleValueField(.mouseEventDeltaY),
                at: now
            )
            canBuffer = false
            alwaysForwardsEvent = true

        case .scrollWheel:
            guard let direction = wheelDirection(of: event) else {
                return event
            }
            output = engine.wheel(direction, modifierFlags: event.flags, at: now)
            canBuffer = false
            alwaysForwardsEvent = false

        default:
            return event
        }

        if let handling = output.pointerHandling {
            switch handling {
            case .forwardAsMovement:
                event.type = .mouseMoved
            case let .remap(target):
                remapMouseEvent(event, to: target)
            }
            output.consumesEvent = false
        } else if let target = remapTarget(in: output.lifecycleEvents) {
            remapMouseEvent(event, to: target)
            output.consumesEvent = false
        }

        let forwardedEvent: DeferredEvent? = if output.forwardsCapturedEvent {
            .init(
                event: event.copy() ?? event,
                sink: context.deferredEventSink ?? fallbackEventSink
            )
        } else {
            nil
        }

        if output.consumesEvent, canBuffer, forwardedEvent == nil {
            bufferedEvents.append(.init(
                event: event.copy() ?? event,
                sink: context.deferredEventSink ?? fallbackEventSink
            ))
        }

        process(output)
        if let forwardedEvent {
            forwardedEvent.sink(forwardedEvent.event)
        }
        scheduleNextDeadline()

        if engine.state == .idle, !output.replaysBufferedEvents {
            bufferedEvents.removeAll()
        }

        if forwardedEvent != nil {
            return nil
        }
        return alwaysForwardsEvent || !output.consumesEvent ? event : nil
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

    private func mappingButton(of event: CGEvent) -> Mapping.Button? {
        guard let mouseButton = MouseEventView(event).mouseButton else {
            return nil
        }

        var number = Int(mouseButton.rawValue)
        if swapsPrimaryAndSecondaryButtons {
            switch number {
            case 0:
                number = 1
            case 1:
                number = 0
            default:
                break
            }
        }
        return .mouse(number)
    }

    private func wheelDirection(of event: CGEvent) -> Mapping.ScrollDirection? {
        let view = ScrollWheelEventView(event)
        guard view.momentumPhase == .none else {
            return nil
        }

        let deltaX = view.continuous ? view.deltaXPt : Double(view.deltaX)
        let deltaY = view.continuous ? view.deltaYPt : Double(view.deltaY)
        guard deltaX != 0 || deltaY != 0 else {
            return nil
        }

        if abs(deltaY) >= abs(deltaX) {
            return deltaY > 0 ? .up : .down
        }
        return deltaX > 0 ? .left : .right
    }

    private func process(_ output: ButtonMappingEngine.Output) {
        for action in output.actions {
            os_log(
                "Matched button action: %{public}@",
                log: Self.log,
                type: .info,
                String(describing: action)
            )
            actionExecutor.perform(action, targetBundleIdentifier: targetBundleIdentifier)
        }

        for lifecycleEvent in output.lifecycleEvents {
            switch lifecycleEvent {
            case let .began(pressAction, buttons):
                if pressAction.behavior == .remap,
                   let target = pressAction.action.remappedMouseButton,
                   !bufferedEvents.isEmpty {
                    replayBufferedEvents(remappingTo: target)
                } else {
                    actionExecutor.beginPress(
                        pressAction,
                        buttons: buttons,
                        targetBundleIdentifier: targetBundleIdentifier
                    )
                }
            case let .ended(pressAction, buttons):
                actionExecutor.endPress(pressAction, buttons: buttons)
            }
        }

        if output.replaysBufferedEvents {
            let events = bufferedEvents
            bufferedEvents.removeAll()
            for deferredEvent in events {
                deferredEvent.sink(deferredEvent.event)
            }
        }
    }

    private func replayBufferedEvents(remappingTo target: CGMouseButton) {
        let events = bufferedEvents
        bufferedEvents.removeAll()
        for deferredEvent in events {
            remapMouseEvent(deferredEvent.event, to: target)
            deferredEvent.sink(deferredEvent.event)
        }
    }

    private func remapTarget(in lifecycleEvents: [ButtonMappingEngine.LifecycleEvent]) -> CGMouseButton? {
        lifecycleEvents.compactMap { lifecycleEvent in
            let pressAction: Mapping.PressAction
            switch lifecycleEvent {
            case let .began(action, _), let .ended(action, _):
                pressAction = action
            }
            guard pressAction.behavior == .remap else {
                return nil
            }
            return pressAction.action.remappedMouseButton
        }
        .last
    }

    private func remapMouseEvent(_ event: CGEvent, to button: CGMouseButton) {
        let view = MouseEventView(event)
        view.modifierFlags = []
        view.mouseButton = button
    }

    private func scheduleNextDeadline() {
        let deadline = engine.nextDeadline
        guard deadline != scheduledDeadline else {
            return
        }

        timerGeneration &+= 1
        let generation = timerGeneration
        timer?.invalidate()
        timer = nil
        scheduledDeadline = deadline

        guard let deadline else {
            return
        }

        scheduleDeadline(deadline, generation: generation)
    }

    private func scheduleDeadline(_ deadline: UInt64, generation: UInt64) {
        let now = monotonicClock()
        let interval = now >= deadline ? 0 : TimeInterval(deadline - now) / 1_000_000_000
        timer = scheduleTimer(interval) { [weak self] in
            self?.deadlineReached(deadline, generation: generation)
        }

        if timer == nil {
            scheduledDeadline = nil
            process(engine.advance(to: deadline))
            scheduleNextDeadline()
        }
    }

    private func deadlineReached(_ deadline: UInt64, generation: UInt64) {
        guard generation == timerGeneration,
              scheduledDeadline == deadline else {
            return
        }

        let now = monotonicClock()
        guard now >= deadline else {
            scheduleDeadline(deadline, generation: generation)
            return
        }

        timer = nil
        scheduledDeadline = nil
        process(engine.advance(to: now))
        scheduleNextDeadline()
    }
}

extension ButtonMappingTransformer: LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult {
        guard !SettingsState.shared.recording else {
            return .notHandled
        }

        let gestureResult = gestureTransformer?.handleLogitechControlEvent(context) ?? .notHandled
        if gestureResult == .handled {
            cancelGestureInteraction(for: context)
            return .handled
        }

        let now = monotonicClock()
        process(engine.advance(to: now))
        targetBundleIdentifier = context.pid?.bundleIdentifier

        guard let button = configuredButton(matching: context) else {
            return gestureResult
        }
        let output = context.isPressed
            ? engine.buttonDown(button, modifierFlags: context.modifierFlags, at: now)
            : engine.buttonUp(button, modifierFlags: context.modifierFlags, at: now)
        process(output)
        scheduleNextDeadline()

        if output.forwardsCapturedEvent {
            return .notHandled
        }
        guard output.consumesEvent else {
            return gestureResult
        }
        if output.replaysBufferedEvents {
            return .notHandled
        }
        return context.isPressed ? .handledDeferringSyntheticFallback : .handled
    }

    private func cancelGestureInteraction(for context: LogitechEventContext) {
        guard let button = configuredButton(matching: context) else {
            return
        }

        let output = engine.cancelInteractions(containing: button)
        guard output.consumesEvent else {
            return
        }
        bufferedEvents.removeAll()
        process(output)
        scheduleNextDeadline()
    }

    private func configuredButton(matching context: LogitechEventContext) -> Mapping.Button? {
        mappings.enumerated()
            .flatMap { mappingIndex, mapping in
                (mapping.trigger?.statefulButtons ?? []).compactMap { button -> (Int, Mapping.Button)? in
                    guard let identity = button.logitechControl,
                          context.matches(identity) else {
                        return nil
                    }
                    let score = identity.specificityScore * 1_000_000 + mappingIndex
                    return (score, button)
                }
            }
            .max { $0.0 < $1.0 }?
            .1
    }
}

extension ButtonMappingTransformer: Deactivatable {
    func deactivate() {
        timerGeneration &+= 1
        timer?.invalidate()
        timer = nil
        scheduledDeadline = nil
        process(engine.reset())
        bufferedEvents.removeAll()
        actionExecutor.deactivate()
        gestureTransformer?.deactivate()
    }
}
