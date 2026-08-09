// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
import Foundation
import os.log

final class AutoScrollTransformer {
    typealias ActivationHitProvider = (CGEvent) -> AutoScrollActivationHit?
    typealias LongPressTimerScheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)?

    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AutoScroll")

    private static let deadZone: Double = 10
    private static let maxScrollStep: Double = 160
    private static let timerInterval: TimeInterval = 1.0 / 60.0

    private let trigger: Scheme.Buttons.Mapping
    private let modes: [Scheme.Buttons.AutoScroll.Mode]
    private let toggleActivation: Scheme.Buttons.AutoScroll.ToggleActivation
    private let speed: Double
    private let scheduleLongPressTimer: LongPressTimerScheduler
    private let activationHitProvider: ActivationHitProvider?
    private let fallbackEventSink: (CGEvent) -> Void

    private enum Session {
        case toggle
        case hold
        case pendingToggleOrHold
    }

    private struct DeferredEvent {
        var event: CGEvent
        var sink: (CGEvent) -> Void
    }

    private enum PendingActivationStrategy {
        case movement(Session)
        case longPress(Session)
        case movementOrLongPress

        var schedulesLongPress: Bool {
            switch self {
            case .longPress, .movementOrLongPress:
                return true
            case .movement:
                return false
            }
        }
    }

    private enum PendingActivationCause {
        case movement
        case longPress
    }

    private struct PendingActivation {
        var anchor: CGPoint
        var current: CGPoint
        var bufferedEvents: [DeferredEvent]
        var strategy: PendingActivationStrategy
        var isPhysicalTrigger: Bool
    }

    private enum State {
        case idle
        case pending(PendingActivation)
        case active(anchor: CGPoint, current: CGPoint, session: Session)
    }

    private var state: State = .idle
    private var suppressTriggerUp = false
    private var suppressedExitMouseButton: CGMouseButton?
    private var longPressTimerCancellation: (() -> Void)?
    private var longPressTimerGeneration: UInt64 = 0
    private var timer: EventThreadTimer?
    private let indicatorController = AutoScrollIndicatorWindowController()
    private let accessibilityActivationClassifier = AutoScrollAccessibilityActivationClassifier()

    static func shouldStartAutoScroll(for hit: AutoScrollActivationHit?) -> Bool {
        hit?.isPressable != true
    }

    init(
        trigger: Scheme.Buttons.Mapping,
        modes: [Scheme.Buttons.AutoScroll.Mode],
        toggleActivation: Scheme.Buttons.AutoScroll.ToggleActivation = .shortPress,
        speed: Double,
        longPressTimerScheduler: @escaping LongPressTimerScheduler = AutoScrollTransformer
            .scheduleEventThreadLongPressTimer,
        activationHitProvider: ActivationHitProvider? = nil,
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    ) {
        self.trigger = trigger
        self.modes = modes
        self.toggleActivation = toggleActivation
        self.speed = speed
        scheduleLongPressTimer = longPressTimerScheduler
        self.activationHitProvider = activationHitProvider
        fallbackEventSink = eventSink
    }

    deinit {
        longPressTimerCancellation?()
        DispatchQueue.main.async { [indicatorController] in
            indicatorController.hide()
        }
    }
}

extension AutoScrollTransformer: EventTransformer, DeferredEventTransformer {
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard !SettingsState.shared.recording else {
            if case .pending = state {
                replayPendingActivation(including: deferredEvent(event, in: context))
                return nil
            }

            cancelInteractionForButtonMappingRecording()
            return event
        }

        if case .pending = state,
           isAnyMouseDownEvent(event),
           !matchesTriggerButton(event) {
            replayPendingActivation(including: deferredEvent(event, in: context))
            return nil
        }

        if case let .active(_, _, session) = state,
           session == .toggle,
           isAnyMouseDownEvent(event),
           !matchesTriggerButton(event) {
            suppressedExitMouseButton = MouseEventView(event).mouseButton
            deactivate()
            return nil
        }

        if let suppressedExitMouseButton,
           isMouseUpEvent(event, for: suppressedExitMouseButton) {
            self.suppressedExitMouseButton = nil
            return nil
        }

        switch event.type {
        case triggerMouseDownEventType:
            return handleTriggerDown(event, in: context)
        case triggerMouseUpEventType:
            return handleTriggerUp(event, in: context)
        case triggerMouseDraggedEventType, .mouseMoved:
            return handlePointerMoved(event, in: context)
        default:
            return event
        }
    }

    private var triggerMouseDownEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseDown)
    }

    private var triggerMouseUpEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseUp)
    }

    private var triggerMouseDraggedEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseDragged)
    }

    private var triggerMouseButton: CGMouseButton {
        let defaultButton = UInt32(CGMouseButton.center.rawValue)
        let buttonNumber = trigger.button?.syntheticMouseButtonNumber ?? Int(defaultButton)
        return CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center
    }

    private var triggerIsLogitechControl: Bool {
        trigger.button?.logitechControl != nil
    }

    private func handleTriggerDown(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard matchesTriggerButton(event) else {
            return event
        }

        if case let .active(_, _, session) = state, session == .toggle {
            guard hasToggleMode else {
                return nil
            }

            deactivate()
            suppressTriggerUp = true
            return nil
        }

        guard matchesActivationTrigger(event) else {
            return event
        }

        if usesLongPressToggle {
            let strategy: PendingActivationStrategy = hasHoldMode
                ? .movementOrLongPress
                : .longPress(.toggle)
            beginPendingActivation(
                with: event,
                in: context,
                strategy: strategy
            )
            return nil
        }

        if isHoldOnlyMode {
            beginPendingActivation(with: event, in: context, strategy: .movement(.hold))
            return nil
        }

        let activationHitResult: AutoScrollActivationHit?
        if let activationHitProvider {
            activationHitResult = activationHitProvider(event)
        } else {
            activationHitResult = activationHit(for: event)
        }
        guard Self.shouldStartAutoScroll(for: activationHitResult) else {
            // Delay the native stream only until movement distinguishes a click from
            // an Auto Scroll drag. A click replays the complete stream in order.
            beginPendingActivation(
                with: event,
                in: context,
                strategy: .movement(activationSession)
            )
            return nil
        }

        activate(at: pointerLocation(for: event), session: activationSession)
        suppressTriggerUp = true
        return nil
    }

    private func handleTriggerUp(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard matchesTriggerButton(event) else {
            return event
        }

        if case .pending = state {
            replayPendingActivation(including: deferredEvent(event, in: context))
            return nil
        }

        guard suppressTriggerUp else {
            return event
        }

        switch state {
        case .pending:
            break

        case let .active(anchor, current, session):
            switch session {
            case .hold:
                deactivate()
            case .pendingToggleOrHold:
                if exceedsDeadZone(from: anchor, to: current) {
                    deactivate()
                } else {
                    state = .active(anchor: anchor, current: current, session: .toggle)
                }
            case .toggle:
                break
            }

        case .idle:
            break
        }

        suppressTriggerUp = false
        return nil
    }

    private func handlePointerMoved(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        switch state {
        case var .pending(pending):
            let isTriggerDrag = event.type == triggerMouseDraggedEventType
                && matchesTriggerButton(event)
            let isLogitechMove = triggerIsLogitechControl && event.type == .mouseMoved
            guard isTriggerDrag || isLogitechMove else {
                return event
            }

            let point = pointerLocation(for: event)
            pending.current = point
            if isTriggerDrag {
                pending.bufferedEvents.append(deferredEvent(event, in: context))
            }
            state = .pending(pending)

            if exceedsDeadZone(from: pending.anchor, to: point),
               activatePending(for: .movement) {
                return handlePointerMoved(event, in: context)
            }

            return isTriggerDrag ? nil : event

        case let .active(anchor, _, session):
            let point = pointerLocation(for: event)
            let resolvedSession: Session
            let isTriggerDrag = event.type == triggerMouseDraggedEventType
                && matchesTriggerButton(event)
            let isDragOrLogitechMove = isTriggerDrag
                || (triggerIsLogitechControl && event.type == .mouseMoved)
            if session == .pendingToggleOrHold,
               isDragOrLogitechMove,
               exceedsDeadZone(from: anchor, to: point) {
                resolvedSession = .hold
            } else {
                resolvedSession = session
            }

            state = .active(anchor: anchor, current: point, session: resolvedSession)
            let delta = CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y)
            DispatchQueue.main.async { [indicatorController] in
                indicatorController.update(delta: delta)
            }

            if isTriggerDrag, suppressTriggerUp {
                return nil
            }

            return event

        case .idle:
            return event
        }
    }

    var isAutoscrollActive: Bool {
        if case .active = state {
            return true
        }
        return false
    }

    private var hasPendingActivation: Bool {
        if case .pending = state {
            return true
        }
        return false
    }

    private func deferredEvent(_ event: CGEvent, in context: EventTransformerContext) -> DeferredEvent {
        .init(
            event: event.copy() ?? event,
            sink: context.deferredEventSink ?? fallbackEventSink
        )
    }

    private func beginPendingActivation(
        with event: CGEvent,
        in context: EventTransformerContext,
        strategy: PendingActivationStrategy
    ) {
        let point = pointerLocation(for: event)
        beginPendingActivation(
            at: point,
            bufferedEvents: [deferredEvent(event, in: context)],
            strategy: strategy,
            isPhysicalTrigger: true
        )
    }

    private func beginPendingActivation(
        at point: CGPoint,
        bufferedEvents: [DeferredEvent],
        strategy: PendingActivationStrategy,
        isPhysicalTrigger: Bool
    ) {
        cancelLongPressTimer()
        state = .pending(.init(
            anchor: point,
            current: point,
            bufferedEvents: bufferedEvents,
            strategy: strategy,
            isPhysicalTrigger: isPhysicalTrigger
        ))

        if strategy.schedulesLongPress {
            schedulePendingLongPressActivation()
        }
    }

    private func replayPendingActivation(including finalEvent: DeferredEvent? = nil) {
        guard case let .pending(pending) = state else {
            return
        }

        state = .idle
        cancelLongPressTimer()
        var events = pending.bufferedEvents
        if let finalEvent {
            events.append(finalEvent)
        }
        for event in events {
            event.sink(event.event)
        }
    }

    @discardableResult
    private func activatePending(for cause: PendingActivationCause) -> Bool {
        guard case let .pending(pending) = state else {
            return false
        }

        let session: Session
        switch (pending.strategy, cause) {
        case let (.movement(pendingSession), .movement),
             let (.longPress(pendingSession), .longPress):
            session = pendingSession
        case (.movementOrLongPress, .movement):
            session = .hold
        case (.movementOrLongPress, .longPress):
            session = .pendingToggleOrHold
        default:
            return false
        }

        cancelLongPressTimer()
        suppressTriggerUp = pending.isPhysicalTrigger
        activate(
            at: pending.anchor,
            current: pending.current,
            session: session
        )
        return true
    }

    private func schedulePendingLongPressActivation() {
        longPressTimerGeneration &+= 1
        let generation = longPressTimerGeneration
        longPressTimerCancellation = scheduleLongPressTimer(
            ButtonMappingPolicy.default.longPressDuration
        ) { [weak self] in
            self?.longPressThresholdReached(generation: generation)
        }
    }

    private func longPressThresholdReached(generation: UInt64) {
        guard generation == longPressTimerGeneration,
              case .pending = state else {
            return
        }

        longPressTimerCancellation = nil
        activatePending(for: .longPress)
    }

    private func cancelLongPressTimer() {
        longPressTimerGeneration &+= 1
        longPressTimerCancellation?()
        longPressTimerCancellation = nil
    }

    private static func scheduleEventThreadLongPressTimer(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> (() -> Void)? {
        guard let timer = EventThread.shared.scheduleTimer(
            interval: interval,
            repeats: false,
            handler: handler
        ) else {
            return nil
        }

        return {
            timer.invalidate()
        }
    }

    private func matchesActivationTrigger(_ event: CGEvent) -> Bool {
        guard matchesTriggerButton(event) else {
            return false
        }

        return trigger.matches(modifierFlags: event.flags)
    }

    private func matchesTriggerButton(_ event: CGEvent) -> Bool {
        guard let eventButton = MouseEventView(event).mouseButton else {
            return false
        }

        return eventButton == triggerMouseButton
    }

    private func isAnyMouseDownEvent(_ event: CGEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    private func isMouseUpEvent(_ event: CGEvent, for button: CGMouseButton) -> Bool {
        guard let eventButton = MouseEventView(event).mouseButton else {
            return false
        }

        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return eventButton == button
        default:
            return false
        }
    }

    private func activate(at point: CGPoint, current: CGPoint? = nil, session: Session) {
        os_log(
            "Auto scroll activated (modes=%{public}@, button=%{public}d)",
            log: Self.log,
            type: .info,
            modes.map(\.rawValue).joined(separator: ","),
            Int(triggerMouseButton.rawValue)
        )

        suppressedExitMouseButton = nil
        let current = current ?? point
        state = .active(anchor: point, current: current, session: session)
        let delta = CGVector(dx: current.x - point.x, dy: current.y - point.y)
        DispatchQueue.main.async { [indicatorController] in
            indicatorController.show(at: point)
            indicatorController.update(delta: delta)
        }
        startTimerIfNeeded()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        timer = EventThread.shared.scheduleTimer(
            interval: Self.timerInterval,
            repeats: true
        ) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        guard case let .active(anchor, current, _) = state else {
            return
        }

        let horizontal = scrollAmount(for: anchor.x - current.x)
        let vertical = scrollAmount(for: current.y - anchor.y)

        guard horizontal != 0 || vertical != 0 else {
            return
        }

        postContinuousScrollEvent(horizontal: horizontal, vertical: vertical)
    }

    private func scrollAmount(for delta: Double) -> Double {
        let adjusted = abs(delta) - Self.deadZone
        guard adjusted > 0 else {
            return 0
        }

        let base = adjusted * speed * 0.12
        let boost = sqrt(adjusted) * speed * 0.6
        let value = min(Self.maxScrollStep, base + boost)

        return delta.sign == .minus ? -value : value
    }

    private func postContinuousScrollEvent(horizontal: Double, vertical: Double) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }

        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontal)
        event.flags = []
        event.post(tap: .cgSessionEventTap)
    }

    private var hasToggleMode: Bool {
        modes.contains(.toggle)
    }

    private var hasHoldMode: Bool {
        modes.contains(.hold)
    }

    private var isHoldOnlyMode: Bool {
        hasHoldMode && !hasToggleMode
    }

    private var usesLongPressToggle: Bool {
        hasToggleMode && toggleActivation == .longPress
    }

    private var activationSession: Session {
        switch (hasToggleMode, hasHoldMode) {
        case (true, true):
            .pendingToggleOrHold
        case (false, true):
            .hold
        default:
            .toggle
        }
    }

    private func pointerLocation(for event: CGEvent) -> CGPoint {
        event.unflippedLocation
    }

    private func exceedsDeadZone(from anchor: CGPoint, to point: CGPoint) -> Bool {
        abs(point.x - anchor.x) > Self.deadZone || abs(point.y - anchor.y) > Self.deadZone
    }

    private func cancelInteractionForButtonMappingRecording() {
        guard hasPendingActivation || isAutoscrollActive || suppressTriggerUp || suppressedExitMouseButton != nil else {
            return
        }

        suppressedExitMouseButton = nil
        deactivate()
    }

    private func hitTestPoint(for event: CGEvent) -> CGPoint {
        event.location
    }

    private func activationHit(for event: CGEvent) -> AutoScrollActivationHit? {
        guard AccessibilityPermission.enabled else {
            return nil
        }

        // Use the event snapshot position instead of re-sampling the current cursor location.
        // This keeps the AX hit-test anchored to the original click we are classifying.
        let point = hitTestPoint(for: event)
        let classification = accessibilityActivationClassifier.classify(at: point)
        logAccessibilityHit(
            initial: classification.initial,
            resolved: classification.resolved
        )
        return classification.resolved.hit
    }

    private func logAccessibilityHit(initial: AutoScrollActivationProbe, resolved: AutoScrollActivationProbe) {
        let initialPointDescription = String(format: "(%.1f, %.1f)", initial.point.x, initial.point.y)
        let resolvedPointDescription = String(format: "(%.1f, %.1f)", resolved.point.x, resolved.point.y)
        let initialPathDescription = initial.hit.path.isEmpty ? "-" : initial.hit.path.joined(separator: " -> ")
        let resolvedPathDescription = resolved.hit.path.isEmpty ? "-" : resolved.hit.path.joined(separator: " -> ")

        if initial.hit.summary == resolved.hit.summary,
           initial.hit.path == resolved.hit.path,
           initial.point == resolved.point {
            os_log(
                "Auto scroll AX hit result=%{public}@ point=%{public}@ path=%{public}@",
                log: Self.log,
                type: .info,
                resolved.hit.summary,
                resolvedPointDescription,
                resolvedPathDescription
            )
            return
        }

        os_log(
            "Auto scroll AX hit initial=%{public}@ initialPoint=%{public}@ initialPath=%{public}@ resolved=%{public}@ resolvedPoint=%{public}@ resolvedPath=%{public}@",
            log: Self.log,
            type: .info,
            initial.hit.summary,
            initialPointDescription,
            initialPathDescription,
            resolved.hit.summary,
            resolvedPointDescription,
            resolvedPathDescription
        )
    }
}

extension AutoScrollTransformer: LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult {
        guard !SettingsState.shared.recording else {
            cancelInteractionForButtonMappingRecording()
            return .notHandled
        }

        guard let triggerLogitechControl = trigger.button?.logitechControl,
              context.matches(triggerLogitechControl) else {
            return .notHandled
        }

        if context.isPressed {
            // If already active in toggle mode, deactivate on re-press
            if case let .active(_, _, session) = state, session == .toggle {
                guard hasToggleMode else {
                    return .handled
                }
                deactivate()
                return .handled
            }

            guard trigger.matches(modifierFlags: context.modifierFlags) else {
                return .notHandled
            }

            if usesLongPressToggle {
                let strategy: PendingActivationStrategy = hasHoldMode
                    ? .movementOrLongPress
                    : .longPress(.toggle)
                beginPendingActivation(
                    at: context.mouseLocation,
                    bufferedEvents: [],
                    strategy: strategy,
                    isPhysicalTrigger: false
                )
                return .handledDeferringSyntheticFallback
            }

            if isHoldOnlyMode {
                beginPendingActivation(
                    at: context.mouseLocation,
                    bufferedEvents: [],
                    strategy: .movement(.hold),
                    isPhysicalTrigger: false
                )
                return .handledDeferringSyntheticFallback
            }

            activate(at: context.mouseLocation, session: activationSession)
            return .handled
        }

        switch state {
        case .pending:
            replayPendingActivation()
            return .notHandled
        case let .active(anchor, current, session):
            switch session {
            case .hold:
                deactivate()
            case .pendingToggleOrHold:
                if exceedsDeadZone(from: anchor, to: current) {
                    deactivate()
                } else {
                    state = .active(anchor: anchor, current: current, session: .toggle)
                }
            case .toggle:
                break
            }
        default:
            break
        }

        return .handled
    }
}

extension AutoScrollTransformer: LogitechControlInteractionCanceling {
    @discardableResult
    func cancelLogitechControlInteraction(_ context: LogitechEventContext) -> Bool {
        guard let triggerLogitechControl = trigger.button?.logitechControl,
              context.matches(triggerLogitechControl),
              hasPendingActivation || isAutoscrollActive else {
            return false
        }

        deactivate()
        return true
    }
}

extension AutoScrollTransformer: Deactivatable {
    func deactivate() {
        replayPendingActivation()
        cancelLongPressTimer()

        if isAutoscrollActive {
            os_log("Auto scroll deactivated", log: Self.log, type: .info)
        }

        state = .idle
        suppressTriggerUp = false
        DispatchQueue.main.async { [indicatorController] in
            indicatorController.hide()
        }

        timer?.invalidate()
        timer = nil
    }
}

extension AutoScrollTransformer {
    func matchesConfiguration(
        trigger: Scheme.Buttons.Mapping,
        modes: [Scheme.Buttons.AutoScroll.Mode],
        toggleActivation: Scheme.Buttons.AutoScroll.ToggleActivation,
        speed: Double
    ) -> Bool {
        self.trigger == trigger &&
            self.modes == modes &&
            self.toggleActivation == toggleActivation &&
            abs(self.speed - speed) < 0.0001
    }
}
