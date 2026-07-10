// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
import Foundation
import os.log

final class AutoScrollTransformer {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AutoScroll")

    private static let deadZone: Double = 10
    private static let maxScrollStep: Double = 160
    private static let timerInterval: TimeInterval = 1.0 / 60.0

    private let trigger: Scheme.Buttons.Mapping
    private let modes: [Scheme.Buttons.AutoScroll.Mode]
    private let speed: Double

    private enum Session {
        case toggle
        case hold
        case pendingToggleOrHold
    }

    private enum State {
        case idle
        case active(anchor: CGPoint, current: CGPoint, session: Session)
    }

    private var state: State = .idle
    private var suppressTriggerUp = false
    private var suppressedExitMouseButton: CGMouseButton?
    private var timer: EventThreadTimer?
    private let indicatorController = AutoScrollIndicatorWindowController()
    private let accessibilityActivationClassifier = AutoScrollAccessibilityActivationClassifier()

    static func shouldStartAutoScroll(for hit: AutoScrollActivationHit?) -> Bool {
        hit?.isPressable != true
    }

    init(
        trigger: Scheme.Buttons.Mapping,
        modes: [Scheme.Buttons.AutoScroll.Mode],
        speed: Double
    ) {
        self.trigger = trigger
        self.modes = modes
        self.speed = speed
    }

    deinit {
        DispatchQueue.main.async { [indicatorController] in
            indicatorController.hide()
        }
    }
}

extension AutoScrollTransformer: EventTransformer {
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
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
            return handleTriggerDown(event)
        case triggerMouseUpEventType:
            return handleTriggerUp(event)
        case triggerMouseDraggedEventType, .mouseMoved:
            return handlePointerMoved(event)
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

    private func handleTriggerDown(_ event: CGEvent) -> CGEvent? {
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

        let activationHit = activationHit(for: event)
        guard Self.shouldStartAutoScroll(for: activationHit) else {
            return event
        }

        activate(at: pointerLocation(for: event), session: activationSession)
        suppressTriggerUp = true
        return nil
    }

    private func handleTriggerUp(_ event: CGEvent) -> CGEvent? {
        guard matchesTriggerButton(event) else {
            return event
        }

        guard suppressTriggerUp else {
            return event
        }

        switch state {
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

    private func handlePointerMoved(_ event: CGEvent) -> CGEvent? {
        switch state {
        case let .active(anchor, _, session):
            let point = pointerLocation(for: event)
            let resolvedSession: Session
            let isDragOrLogitechMove = event.type == triggerMouseDraggedEventType
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

            if event.type == triggerMouseDraggedEventType, suppressTriggerUp {
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

    private func activate(at point: CGPoint, session: Session) {
        os_log(
            "Auto scroll activated (modes=%{public}@, button=%{public}d)",
            log: Self.log,
            type: .info,
            modes.map(\.rawValue).joined(separator: ","),
            Int(triggerMouseButton.rawValue)
        )

        suppressedExitMouseButton = nil
        state = .active(anchor: point, current: point, session: session)
        DispatchQueue.main.async { [indicatorController] in
            indicatorController.show(at: point)
            indicatorController.update(delta: .zero)
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
                return .handled
            }

            activate(at: context.mouseLocation, session: activationSession)
            return .handled
        }

        switch state {
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

extension AutoScrollTransformer: Deactivatable {
    func deactivate() {
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
        speed: Double
    ) -> Bool {
        self.trigger == trigger &&
            self.modes == modes &&
            abs(self.speed - speed) < 0.0001
    }
}
