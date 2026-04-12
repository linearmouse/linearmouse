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
    private let actions: Scheme.Buttons.Gesture.Actions

    /// State machine
    private enum State {
        case idle
        case tracking(startTime: UInt64, deltaX: Double, deltaY: Double)
        case triggered
        case cooldown(until: UInt64)
    }

    private var state: State = .idle

    init(
        trigger: Scheme.Buttons.Mapping,
        threshold: Double,
        deadZone: Double,
        cooldownMs: Int,
        actions: Scheme.Buttons.Gesture.Actions
    ) {
        self.trigger = trigger
        let defaultButton = UInt32(CGMouseButton.center.rawValue)
        let buttonNumber = trigger.button?.syntheticMouseButtonNumber ?? Int(defaultButton)
        triggerMouseButton = CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center
        self.threshold = threshold
        self.deadZone = deadZone
        self.cooldownMs = cooldownMs
        self.actions = actions
    }
}

extension GestureButtonTransformer: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        // Check if we're in cooldown
        if case let .cooldown(until) = state {
            if DispatchTime.now().uptimeNanoseconds < until {
                // Still in cooldown - consume our button events
                if matchesTriggerButton(event) {
//                    os_log("Event consumed during cooldown", log: Self.log, type: .debug)
                    return nil
                }
                return event
            }
            // Cooldown expired, return to idle
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
                state = .cooldown(until: DispatchTime.now().uptimeNanoseconds + cooldownNanos)

                os_log("Entering cooldown for %d ms", log: Self.log, type: .info, cooldownMs)
            } catch {
                os_log("Failed to execute gesture: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                state = .idle
            }

            // Consume the event
            return nil
        }

        // Update state with new deltas
        state = .tracking(startTime: startTime, deltaX: deltaX, deltaY: deltaY)

        // Consume drag events while tracking; pass through mouseMoved events
        return isMouseMoved ? event : nil
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

        // If we triggered, stay in cooldown and consume the event
        if case .triggered = state {
            let cooldownNanos = UInt64(cooldownMs) * 1_000_000
            state = .cooldown(until: DispatchTime.now().uptimeNanoseconds + cooldownNanos)
            return nil
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

extension GestureButtonTransformer {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> Bool {
        guard let triggerLogitechControl = trigger.button?.logitechControl,
              context.controlIdentity.matches(triggerLogitechControl) else {
            return false
        }

        // Dispatch state mutation to the event processing thread to maintain single-threaded access.
        GlobalEventTap.performOnEventThread { [self] in
            // Check cooldown
            if case let .cooldown(until) = state {
                if DispatchTime.now().uptimeNanoseconds < until {
                    return
                }
                state = .idle
            }

            if context.isPressed {
                guard trigger.matches(modifierFlags: context.modifierFlags) else {
                    return
                }
                state = .tracking(startTime: DispatchTime.now().uptimeNanoseconds, deltaX: 0, deltaY: 0)
                os_log("Started tracking gesture (Logitech control)", log: Self.log, type: .info)
            } else {
                switch state {
                case .tracking:
                    state = .idle
                case .cooldown:
                    break
                default:
                    break
                }
            }
        }
        return true
    }
}

extension GestureButtonTransformer: Deactivatable {
    func deactivate() {
        state = .idle
    }
}
