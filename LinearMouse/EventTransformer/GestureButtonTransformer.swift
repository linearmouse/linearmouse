// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import DockKit
import Foundation
import IOKit.hidsystem
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
        case cooldown(until: UInt64, released: Bool)
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
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard !SettingsState.shared.recording || hasActiveInteraction else {
            return event
        }

        // Check if we're in cooldown
        if case let .cooldown(until, released) = state {
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
        
        case .previousTrack:
            postMediaKey(NX_KEYTYPE_PREVIOUS)

        case .nextTrack:
            postMediaKey(NX_KEYTYPE_NEXT)

        case .maximizeWindow:
            break

        case .minimizeWindow:
            break
        }
    }
    private func postMediaKey(_ key: Int32) {
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xA << 8)),
            data2: -1
        )

        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xB00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xB << 8)),
            data2: -1
        )

        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
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
