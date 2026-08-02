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

    private final class RecognitionLane {
        var engine: ButtonMappingEngine
        var bufferedEvents = [DeferredEvent]()

        init(engine: ButtonMappingEngine) {
            self.engine = engine
        }
    }

    private struct RecognitionResult {
        var lane: RecognitionLane?
        var output: ButtonMappingEngine.Output
    }

    private struct RecognitionTrial {
        var lane: RecognitionLane?
        var engine: ButtonMappingEngine
        var output: ButtonMappingEngine.Output
        var order: Int
    }

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ButtonMapping"
    )

    let mappings: [Mapping]
    let universalBackForward: Scheme.Buttons.UniversalBackForward?
    private let actionExecutor: ButtonActionExecutor
    private let scheduleTimer: TimerScheduler
    private let monotonicClock: MonotonicClock
    private let fallbackEventSink: (CGEvent) -> Void
    private let swapsPrimaryAndSecondaryButtons: Bool
    private let gestureTransformer: GestureButtonTransformer?
    private let policy: ButtonMappingPolicy

    private var timer: TimerToken?
    private var timerGeneration: UInt64 = 0
    private var scheduledDeadline: UInt64?
    private var recognitionLanes = [RecognitionLane]()
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
        self.policy = policy
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
        let isRecording = SettingsState.shared.recording
        guard !event.isLinearMouseSyntheticEvent,
              !isRecording || hasActiveInteraction else {
            return event
        }

        if let gestureTransformer,
           !isRecording || gestureTransformer.hasActiveInteraction,
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
        advanceRecognitionLanes(to: now)

        if event.isGestureCleanupRelease,
           let button = mappingButton(of: event) {
            var canceledRemapTarget: CGMouseButton?
            var canceled = false
            for lane in recognitionLanes {
                let cancellation = lane.engine.cancelInteractions(containing: button)
                guard cancellation.consumesEvent else {
                    continue
                }
                canceled = true
                canceledRemapTarget = remapTarget(in: cancellation.lifecycleEvents) ?? canceledRemapTarget
                process(cancellation, in: lane)
            }
            if canceled {
                pruneRecognitionLanes()
                scheduleNextDeadline()
                if let canceledRemapTarget {
                    remapMouseEvent(event, to: canceledRemapTarget)
                    return event
                }
                return nil
            }
        }

        if let targetBundleIdentifier = MouseEventView(event).targetPid?.bundleIdentifier {
            self.targetBundleIdentifier = targetBundleIdentifier
        }

        let recognition: RecognitionResult
        let canBuffer: Bool
        let alwaysForwardsEvent: Bool

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard let button = mappingButton(of: event) else {
                return event
            }
            if isRecording,
               !recognitionLanes.contains(where: { $0.engine.ownsInteraction(containing: button) }) {
                return event
            }
            recognition = recognize(includingFreshLane: !isRecording) { engine in
                engine.buttonDown(button, modifierFlags: event.flags, at: now)
            }
            canBuffer = true
            alwaysForwardsEvent = false

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard let button = mappingButton(of: event) else {
                return event
            }
            recognition = recognize { engine in
                engine.buttonUp(button, modifierFlags: event.flags, at: now)
            }
            canBuffer = true
            alwaysForwardsEvent = false

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let button = mappingButton(of: event)
            recognition = recognize { engine in
                engine.pointerMoved(
                    for: button,
                    deltaX: event.getDoubleValueField(.mouseEventDeltaX),
                    deltaY: event.getDoubleValueField(.mouseEventDeltaY),
                    at: now
                )
            }
            canBuffer = true
            alwaysForwardsEvent = false

        case .mouseMoved:
            recognition = recognize { engine in
                engine.pointerMoved(
                    deltaX: event.getDoubleValueField(.mouseEventDeltaX),
                    deltaY: event.getDoubleValueField(.mouseEventDeltaY),
                    at: now
                )
            }
            canBuffer = false
            alwaysForwardsEvent = true

        case .scrollWheel:
            guard !isRecording else {
                return event
            }
            guard let direction = wheelDirection(of: event) else {
                return event
            }
            recognition = recognize(includingFreshLane: true) { engine in
                engine.wheel(direction, modifierFlags: event.flags, at: now)
            }
            canBuffer = false
            alwaysForwardsEvent = false

        default:
            return event
        }

        var output = recognition.output

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

        if output.consumesEvent, output.buffersEvent, canBuffer, forwardedEvent == nil {
            recognition.lane?.bufferedEvents.append(.init(
                event: event.copy() ?? event,
                sink: context.deferredEventSink ?? fallbackEventSink
            ))
        }

        process(output, in: recognition.lane)
        if let forwardedEvent {
            forwardedEvent.sink(forwardedEvent.event)
        }
        pruneRecognitionLanes()
        scheduleNextDeadline()

        if forwardedEvent != nil {
            return nil
        }
        return alwaysForwardsEvent || !output.consumesEvent ? event : nil
    }

    private func recognize(
        includingFreshLane: Bool = false,
        operation: (inout ButtonMappingEngine) -> ButtonMappingEngine.Output
    ) -> RecognitionResult {
        var trials = recognitionLanes.enumerated().compactMap { index, lane -> RecognitionTrial? in
            var candidateEngine = lane.engine
            let output = operation(&candidateEngine)
            guard output.consumesEvent else {
                return nil
            }
            return .init(lane: lane, engine: candidateEngine, output: output, order: index)
        }

        if includingFreshLane {
            var candidateEngine = ButtonMappingEngine(mappings: mappings, policy: policy)
            let output = operation(&candidateEngine)
            if output.consumesEvent {
                trials.append(.init(
                    lane: nil,
                    engine: candidateEngine,
                    output: output,
                    order: recognitionLanes.count
                ))
            }
        }

        guard let selected = trials.max(by: recognitionTrialIsLowerPriority) else {
            return .init(lane: nil, output: .init())
        }

        if let lane = selected.lane {
            lane.engine = selected.engine
            return .init(lane: lane, output: selected.output)
        }

        guard selected.engine.hasActiveInteraction || selected.output.buffersEvent else {
            return .init(lane: nil, output: selected.output)
        }

        let lane = RecognitionLane(engine: selected.engine)
        recognitionLanes.append(lane)
        return .init(lane: lane, output: selected.output)
    }

    private func recognitionTrialIsLowerPriority(_ lhs: RecognitionTrial, _ rhs: RecognitionTrial) -> Bool {
        let lhsStatePriority = recognitionStatePriority(lhs.engine.state)
        let rhsStatePriority = recognitionStatePriority(rhs.engine.state)
        if lhsStatePriority != rhsStatePriority {
            return lhsStatePriority < rhsStatePriority
        }

        let lhsPriority = lhs.output.recognitionPriority ?? Int.min
        let rhsPriority = rhs.output.recognitionPriority ?? Int.min
        if lhsPriority == rhsPriority {
            return lhs.order > rhs.order
        }
        return lhsPriority < rhsPriority
    }

    private func recognitionStatePriority(_ state: ButtonMappingEngine.State) -> Int {
        switch state {
        case .idle:
            return 0
        case .waitingForChord:
            return 1
        case .tracking:
            return 2
        case .committed:
            return 3
        }
    }

    private func advanceRecognitionLanes(to timestamp: UInt64) {
        for lane in recognitionLanes {
            process(lane.engine.advance(to: timestamp), in: lane)
        }
        pruneRecognitionLanes()
    }

    private func pruneRecognitionLanes() {
        recognitionLanes.removeAll { lane in
            !lane.engine.hasActiveInteraction && lane.bufferedEvents.isEmpty
        }
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

    private func process(_ output: ButtonMappingEngine.Output, in lane: RecognitionLane?) {
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
                   lane?.bufferedEvents.isEmpty == false {
                    replayBufferedEvents(in: lane, remappingTo: target)
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
            let events = lane?.bufferedEvents ?? []
            lane?.bufferedEvents.removeAll()
            for deferredEvent in events {
                deferredEvent.sink(deferredEvent.event)
            }
        } else if output.discardsBufferedEvents {
            lane?.bufferedEvents.removeAll()
        }
    }

    private func replayBufferedEvents(in lane: RecognitionLane?, remappingTo target: CGMouseButton) {
        let events = lane?.bufferedEvents ?? []
        lane?.bufferedEvents.removeAll()
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
        let deadline = recognitionLanes.compactMap(\.engine.nextDeadline).min()
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
            advanceRecognitionLanes(to: deadline)
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
        advanceRecognitionLanes(to: now)
        scheduleNextDeadline()
    }
}

extension ButtonMappingTransformer: LogitechControlEventHandling, LogitechControlInteractionCanceling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult {
        let isRecording = SettingsState.shared.recording
        guard !isRecording || hasActiveInteraction else {
            return .notHandled
        }

        let gestureResult: LogitechControlEventHandlingResult = if !isRecording ||
            gestureTransformer?.hasActiveInteraction == true {
            gestureTransformer?.handleLogitechControlEvent(context) ?? .notHandled
        } else {
            .notHandled
        }
        if gestureResult == .handled {
            cancelGestureInteraction(for: context)
            return .handled
        }

        let now = monotonicClock()
        advanceRecognitionLanes(to: now)
        targetBundleIdentifier = context.pid?.bundleIdentifier

        let configuredButtons = configuredButtons(matching: context)
        guard !configuredButtons.isEmpty else {
            return gestureResult
        }
        if isRecording,
           context.isPressed,
           !recognitionLanes.contains(where: { lane in
               configuredButtons.contains { lane.engine.ownsInteraction(containing: $0) }
           }) {
            return gestureResult
        }
        let recognition: RecognitionResult
        if context.isPressed {
            recognition = recognize(includingFreshLane: !isRecording) { engine in
                engine.buttonDown(
                    firstMatching: configuredButtons,
                    modifierFlags: context.modifierFlags,
                    at: now
                )
                .output
            }
        } else {
            recognition = recognize { engine in
                engine.buttonUp(
                    firstMatching: configuredButtons,
                    modifierFlags: context.modifierFlags,
                    at: now
                )
                .output
            }
        }
        process(recognition.output, in: recognition.lane)
        pruneRecognitionLanes()
        scheduleNextDeadline()

        if recognition.output.forwardsCapturedEvent {
            return .handledAllowingSyntheticFallback
        }
        guard recognition.output.consumesEvent else {
            return gestureResult
        }
        if recognition.output.replaysBufferedEvents {
            return .handledAllowingSyntheticFallback
        }
        return context.isPressed ? .handledDeferringSyntheticFallback : .handled
    }

    private func cancelGestureInteraction(for context: LogitechEventContext) {
        _ = cancelMappingInteractions(
            for: configuredButtons(matching: context),
            replayingBufferedEvents: false
        )
    }

    @discardableResult
    func cancelLogitechControlInteraction(_ context: LogitechEventContext) -> Bool {
        let canceledGesture = gestureTransformer?.cancelLogitechControlInteraction(context) == true
        let canceledMapping = cancelMappingInteractions(
            for: configuredButtons(matching: context),
            replayingBufferedEvents: true
        )
        return canceledGesture || canceledMapping
    }

    private func cancelMappingInteractions(
        for buttons: [Mapping.Button],
        replayingBufferedEvents: Bool
    ) -> Bool {
        var canceled = false
        for lane in recognitionLanes {
            var cancellation = ButtonMappingEngine.Output()
            for button in buttons {
                cancellation.append(lane.engine.cancelInteractions(
                    containing: button,
                    replayingBufferedEvents: replayingBufferedEvents
                ))
            }
            guard cancellation.consumesEvent else {
                continue
            }
            canceled = true
            process(cancellation, in: lane)
        }
        if canceled {
            pruneRecognitionLanes()
            scheduleNextDeadline()
        }
        return canceled
    }

    private func configuredButtons(matching context: LogitechEventContext) -> [Mapping.Button] {
        let scoredButtons = mappings.enumerated().reduce(into: [Mapping.Button: Int]()) { result, item in
            let (mappingIndex, mapping) = item
            for button in mapping.trigger?.statefulButtons ?? [] {
                guard let identity = button.logitechControl,
                      context.matches(identity) else {
                    continue
                }
                let score = identity.specificityScore * 1_000_000 + mappingIndex
                result[button] = max(result[button] ?? Int.min, score)
            }
        }

        return scoredButtons
            .sorted { lhs, rhs in lhs.value > rhs.value }
            .map(\.key)
    }
}

extension ButtonMappingTransformer: Deactivatable {
    func deactivate() {
        timerGeneration &+= 1
        timer?.invalidate()
        timer = nil
        scheduledDeadline = nil
        for lane in recognitionLanes {
            process(lane.engine.reset(), in: lane)
            lane.bufferedEvents.removeAll()
        }
        recognitionLanes.removeAll()
        actionExecutor.deactivate()
        gestureTransformer?.deactivate()
    }
}

extension ButtonMappingTransformer: EventTransformerInteractionTracking {
    var hasActiveInteraction: Bool {
        recognitionLanes.contains(where: \.engine.hasActiveInteraction)
            || gestureTransformer?.hasActiveInteraction == true
    }
}
