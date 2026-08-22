// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import DockKit
import Foundation
import KeyKit
import os.log

class GestureButtonTransformer {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GestureButton")

    // Configuration
    private let trigger: Scheme.Buttons.Mapping
    private let triggerMouseButton: CGMouseButton
    private let threshold: Double
    private let deadZone: Double
    private let cooldownMs: Int
    private let suppressPointerMovement: Bool
    private let actions: Scheme.Buttons.Gesture.Actions
    private let warpPointer: (CGPoint) -> Void

    /// State machine
    private enum State {
        case idle
        case tracking(startTime: UInt64, deltaX: Double, deltaY: Double)
        case triggered
        case cooldown(until: UInt64, released: Bool)
    }

    private var state: State = .idle

    init(
        trigger: Scheme.Buttons.Mapping,
        threshold: Double,
        deadZone: Double,
        cooldownMs: Int,
        suppressPointerMovement: Bool,
        actions: Scheme.Buttons.Gesture.Actions,
        warpPointer: @escaping (CGPoint) -> Void = { position in
            _ = CGWarpMouseCursorPosition(position)
        }
    ) {
        self.trigger = trigger
        let defaultButton = UInt32(CGMouseButton.center.rawValue)
        let buttonNumber = trigger.button?.syntheticMouseButtonNumber ?? Int(defaultButton)
        triggerMouseButton = CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center
        self.threshold = threshold
        self.deadZone = deadZone
        self.cooldownMs = cooldownMs
        self.suppressPointerMovement = suppressPointerMovement
        self.actions = actions
        self.warpPointer = warpPointer
    }
}

extension GestureButtonTransformer: EventTransformer {
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard !SettingsState.shared.recording || hasActiveInteraction else {
            return event
        }

        // Check if we're in cooldown
        if case let .cooldown(until, released) = state {
            // Logitech gesture controls report pointer movement without a
            // button number. Keep the pointer stationary until their trigger
            // release, even after a gesture has entered cooldown.
            if suppressPointerMovement, !released, event.type == .mouseMoved {
                return suppressPointerMovementEvent(event)
            }

            if DispatchTime.now().uptimeNanoseconds < until {
                // Still in cooldown - consume our button events
                if matchesTriggerButton(event) {
                    if event.type == mouseUpEventType, !released {
                        os_log("Releasing trigger button during cooldown", log: Self.log, type: .debug)
                        state = .cooldown(until: until, released: true)
                        event.isGestureCleanupRelease = true
                        return event
                    }
                    os_log("Event consumed during cooldown", log: Self.log, type: .debug)
                    return nil
                }
                return event
            }

            // The action cooldown may expire before the physical button is
            // released. Keep ownership until that release so lower-priority
            // click recognizers cannot treat it as a fresh short press.
            if !released {
                guard matchesTriggerButton(event) else {
                    return event
                }
                if event.type == mouseUpEventType {
                    state = .idle
                    event.isGestureCleanupRelease = true
                    return event
                }
                return nil
            }

            state = .idle
        }

        // Route based on event type
        switch event.type {
        case mouseDownEventType:
            return handleButtonDown(event)
        case mouseDraggedEventType, .mouseMoved:
            return handleDragged(event)
        case mouseUpEventType:
            return handleButtonUp(event)
        default:
            return event
        }
    }

    private var mouseDownEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseDown)
    }

    private var mouseUpEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseUp)
    }

    private var mouseDraggedEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseDragged)
    }

    private func matchesTriggerButton(_ event: CGEvent) -> Bool {
        guard let eventButton = MouseEventView(event).mouseButton else {
            return false
        }
        return eventButton == triggerMouseButton
    }

    private func matchesActivationTrigger(_ event: CGEvent) -> Bool {
        guard matchesTriggerButton(event) else {
            return false
        }
        return trigger.matches(modifierFlags: event.flags)
    }

    private func handleButtonDown(_ event: CGEvent) -> CGEvent? {
        guard matchesActivationTrigger(event) else {
            return event
        }

        // Start tracking
        state = .tracking(startTime: DispatchTime.now().uptimeNanoseconds, deltaX: 0, deltaY: 0)
//        os_log("Started tracking gesture", log: Self.log, type: .info)

        // Pass through the button down event
        return event
    }

    private func handleDragged(_ event: CGEvent) -> CGEvent? {
        guard case .tracking(let startTime, var deltaX, var deltaY) = state else {
            return event
        }

        let isMouseMoved = event.type == .mouseMoved

        // For drag events, verify button match.
        // mouseMoved events don't carry a button number but are used to track
        // movement when the trigger is a Logitech HID++ control (which generates
        // synthetic button events that don't produce OS-level drag events).
        if !isMouseMoved {
            guard matchesTriggerButton(event) else {
                return event
            }
        }

        // Accumulate deltas
        let eventDeltaX = event.getDoubleValueField(.mouseEventDeltaX)
        let eventDeltaY = event.getDoubleValueField(.mouseEventDeltaY)
        deltaX += eventDeltaX
        deltaY += eventDeltaY

//        os_log("Accumulated delta: (%.2f, %.2f)", log: Self.log, type: .debug, deltaX, deltaY)

        // Check for timeout (3 seconds)
        let elapsed = DispatchTime.now().uptimeNanoseconds - startTime
        if elapsed > 3_000_000_000 {
//            os_log("Gesture timeout, resetting", log: Self.log, type: .info)
            state = .idle
            return event
        }

        // Check if threshold is met
        if let action = detectGesture(deltaX: deltaX, deltaY: deltaY) {
            os_log("Gesture detected: %{public}@", log: Self.log, type: .info, String(describing: action))

            // Execute the gesture
            do {
                try executeGesture(action)
                state = .triggered

                // Enter cooldown
                let cooldownNanos = UInt64(cooldownMs) * 1_000_000
                state = .cooldown(until: DispatchTime.now().uptimeNanoseconds + cooldownNanos, released: false)

                os_log("Entering cooldown for %d ms", log: Self.log, type: .info, cooldownMs)
            } catch {
                os_log("Failed to execute gesture: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                state = .idle
            }

            // Consume the event. mouseMoved still changes the system cursor
            // unless its pre-event location is restored explicitly.
            return isMouseMoved && suppressPointerMovement
                ? suppressPointerMovementEvent(event)
                : nil
        }

        // Update state with new deltas
        state = .tracking(startTime: startTime, deltaX: deltaX, deltaY: deltaY)

        // Drag events are always consumed. Logitech gesture controls report
        // movement as mouseMoved, which remains opt-in to preserve existing
        // pointer behavior.
        if isMouseMoved, suppressPointerMovement {
            return suppressPointerMovementEvent(event)
        }
        return isMouseMoved ? event : nil
    }

    /// Returning nil from a HID event tap does not prevent macOS from moving
    /// the cursor for mouseMoved events, so restore the pre-event location too.
    private func suppressPointerMovementEvent(_ event: CGEvent) -> CGEvent? {
        warpPointer(event.location)
        return nil
    }

    private func handleButtonUp(_ event: CGEvent) -> CGEvent? {
        guard matchesTriggerButton(event) else {
            return event
        }

        // If we were tracking but didn't trigger, reset to idle
        if case .tracking = state {
//            os_log("Button released before threshold, resetting", log: Self.log, type: .info)
            state = .idle
            // Pass through the button up event so it can be used as a normal click
            return event
        }

        // If we triggered, enter cooldown and pass the release through
        if case .triggered = state {
            let cooldownNanos = UInt64(cooldownMs) * 1_000_000
            state = .cooldown(until: DispatchTime.now().uptimeNanoseconds + cooldownNanos, released: true)
            event.isGestureCleanupRelease = true
            return event
        }

        return event
    }

    private func detectGesture(deltaX: Double, deltaY: Double) -> Scheme.Buttons.Gesture.GestureAction? {
        let absDeltaX = abs(deltaX)
        let absDeltaY = abs(deltaY)

        // Calculate magnitude
        let magnitude = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard magnitude >= threshold else {
            return nil
        }

//        os_log(
//            "Gesture check: deltaX=%.1f, deltaY=%.1f, magnitude=%.1f, deadZone=%.1f",
//            log: Self.log,
//            type: .info,
//            deltaX,
//            deltaY,
//            magnitude,
//            deadZone
//        )

        // Determine dominant axis
        if absDeltaX > absDeltaY {
            // Horizontal gesture
            guard absDeltaY < deadZone else {
//                os_log(
//                    "Horizontal gesture rejected: absDeltaY=%.1f >= deadZone=%.1f",
//                    log: Self.log,
//                    type: .info,
//                    absDeltaY,
//                    deadZone
//                )
                return nil
            }
            // Use defaults if actions not configured
            return deltaX > 0 ? (actions.right ?? .spaceRight) : (actions.left ?? .spaceLeft)
        }
        // Vertical gesture
        guard absDeltaX < deadZone else {
//                os_log(
//                    "Vertical gesture rejected: absDeltaX=%.1f >= deadZone=%.1f",
//                    log: Self.log,
//                    type: .info,
//                    absDeltaX,
//                    deadZone
//                )
            return nil
        }
        // Use defaults if actions not configured
        return deltaY > 0 ? (actions.down ?? .appExpose) : (actions.up ?? .missionControl)
    }

    private func executeGesture(_ action: Scheme.Buttons.Gesture.GestureAction) throws {
        switch action {
        case .none:
            break

        case .spaceLeft:
            try postSymbolicHotKey(.spaceLeft)

        case .spaceRight:
            try postSymbolicHotKey(.spaceRight)

        case .missionControl:
            missionControl()

        case .appExpose:
            appExpose()

        case .showDesktop:
            showDesktop()

        case .launchpad:
            launchpad()
        }
    }
}

extension GestureButtonTransformer: LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult {
        guard !SettingsState.shared.recording || hasActiveInteraction else {
            return .notHandled
        }

        guard let triggerLogitechControl = trigger.button?.logitechControl,
              context.matches(triggerLogitechControl) else {
            return .notHandled
        }

        if case let .cooldown(until, released) = state {
            if DispatchTime.now().uptimeNanoseconds < until {
                if context.isPressed || released {
                    return .handled
                }

                state = .cooldown(until: until, released: true)
                return .handled
            }

            if !released {
                if context.isPressed {
                    return .handled
                }
                state = .idle
                return .handled
            }

            state = .idle
        }

        if context.isPressed {
            guard trigger.matches(modifierFlags: context.modifierFlags) else {
                return .notHandled
            }
            state = .tracking(startTime: DispatchTime.now().uptimeNanoseconds, deltaX: 0, deltaY: 0)
            os_log("Started tracking gesture (Logitech control)", log: Self.log, type: .info)
            return .handledDeferringSyntheticFallback
        }

        switch state {
        case .tracking:
            state = .idle
        default:
            break
        }

        return .notHandled
    }
}

extension GestureButtonTransformer: LogitechControlInteractionCanceling {
    @discardableResult
    func cancelLogitechControlInteraction(_ context: LogitechEventContext) -> Bool {
        guard let triggerLogitechControl = trigger.button?.logitechControl,
              context.matches(triggerLogitechControl),
              hasActiveInteraction else {
            return false
        }

        state = .idle
        return true
    }
}

extension GestureButtonTransformer {
    var configuredTriggerButton: Scheme.Buttons.Mapping.Button? {
        trigger.button
    }

    /// Stops a still-pending Gesture Button interaction after another
    /// recognizer has committed the same button stream first.
    @discardableResult
    func cancelInteraction(containing button: Scheme.Buttons.Mapping.Button) -> Bool {
        guard trigger.button?.canRepresentSamePhysicalInput(as: button) == true,
              hasActiveInteraction else {
            return false
        }

        state = .idle
        return true
    }
}

extension GestureButtonTransformer: Deactivatable {
    func deactivate() {
        state = .idle
    }
}

extension GestureButtonTransformer: EventTransformerInteractionTracking {
    var hasActiveInteraction: Bool {
        switch state {
        case .idle:
            return false
        case .tracking, .triggered:
            return true
        case let .cooldown(_, released):
            return !released
        }
    }
}
