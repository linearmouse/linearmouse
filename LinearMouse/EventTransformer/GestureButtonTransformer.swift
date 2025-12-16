// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import DockKit
import Foundation
import KeyKit
import os.log

class GestureButtonTransformer {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GestureButton")

    // Configuration
    private let button: CGMouseButton
    private let threshold: Double
    private let deadZone: Double
    private let cooldownMs: Int
    private let actions: Scheme.Buttons.Gesture.Actions

    // State machine
    private enum State {
        case idle
        case tracking(startTime: UInt64, deltaX: Double, deltaY: Double)
        case triggered
        case cooldown(until: UInt64)
    }

    private var state: State = .idle

    init(
        button: CGMouseButton,
        threshold: Double,
        deadZone: Double,
        cooldownMs: Int,
        actions: Scheme.Buttons.Gesture.Actions
    ) {
        self.button = button
        self.threshold = threshold
        self.deadZone = deadZone
        self.cooldownMs = cooldownMs
        self.actions = actions

//        os_log(
//            "GestureButtonTransformer initialized - button: %d, threshold: %.1f",
//            log: Self.log,
//            type: .info,
//            button.rawValue,
//            threshold
//        )
    }
}

extension GestureButtonTransformer: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        // Check if we're in cooldown
        if case let .cooldown(until) = state {
            if DispatchTime.now().uptimeNanoseconds < until {
                // Still in cooldown - consume our button events
                if isOurButtonEvent(event) {
//                    os_log("Event consumed during cooldown", log: Self.log, type: .debug)
                    return nil
                }
                return event
            } else {
                // Cooldown expired, return to idle
                state = .idle
            }
        }

        // Route based on event type
        switch event.type {
        case mouseDownEventType:
            return handleButtonDown(event)
        case mouseDraggedEventType:
            return handleDragged(event)
        case mouseUpEventType:
            return handleButtonUp(event)
        default:
            return event
        }
    }

    private var mouseDownEventType: CGEventType {
        button.fixedCGEventType(of: .otherMouseDown)
    }

    private var mouseUpEventType: CGEventType {
        button.fixedCGEventType(of: .otherMouseUp)
    }

    private var mouseDraggedEventType: CGEventType {
        button.fixedCGEventType(of: .otherMouseDragged)
    }

    private func isOurButtonEvent(_ event: CGEvent) -> Bool {
        let mouseEventView = MouseEventView(event)
        guard let eventButton = mouseEventView.mouseButton else {
            return false
        }
        return eventButton == button
    }

    private func handleButtonDown(_ event: CGEvent) -> CGEvent? {
        guard isOurButtonEvent(event) else {
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

        guard isOurButtonEvent(event) else {
            return event
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

            // Consume the drag event
            return nil
        }

        // Update state with new deltas
        state = .tracking(startTime: startTime, deltaX: deltaX, deltaY: deltaY)

        // Consume the drag event while tracking
        return nil
    }

    private func handleButtonUp(_ event: CGEvent) -> CGEvent? {
        guard isOurButtonEvent(event) else {
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
        } else {
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

extension GestureButtonTransformer: Deactivatable {
    func deactivate() {
//        os_log("Deactivating gesture transformer", log: Self.log, type: .info)
        state = .idle
    }
}
