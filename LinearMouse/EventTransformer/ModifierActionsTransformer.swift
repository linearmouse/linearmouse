// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import GestureKit
import KeyKit
import os.log

class ModifierActionsTransformer {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ModifierActionsTransformer"
    )

    private static let defaultKeySimulator = KeySimulator(
        eventSourceUserData: CGEvent.linearMouseSyntheticEventUserData
    )

    typealias Modifiers = Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Modifiers>
    typealias Action = Scheme.Scrolling.Modifiers.Action

    private let modifiers: Modifiers
    private let keySimulator: KeySimulating

    private var pinchZoomBegan = false
    private var pinchZoomReversed = false

    init(modifiers: Modifiers, keySimulator: KeySimulating? = nil) {
        self.modifiers = modifiers
        self.keySimulator = keySimulator ?? Self.defaultKeySimulator
    }
}

extension ModifierActionsTransformer: EventTransformer {
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        if pinchZoomBegan {
            return handlePinchZoom(event, reverse: pinchZoomReversed)
        }

        guard event.type == .scrollWheel else {
            return event
        }

        let scrollWheelEventView = ScrollWheelEventView(event)
        guard let modifiers = scrollWheelEventView.deltaYSignum != 0
            ? modifiers.vertical
            : modifiers.horizontal else {
            return event
        }

        let actions: [(CGEventFlags.Element, Action?)] = [
            (.maskCommand, modifiers.command),
            (.maskShift, modifiers.shift),
            (.maskAlternate, modifiers.option),
            (.maskControl, modifiers.control)
        ]
        var event = event
        for case let (flag, action) in actions where event.flags.contains(flag) {
            if let action, action != .auto {
                guard let handledEvent = handleModifierKeyAction(for: event, action: action) else {
                    return nil
                }
                event = handledEvent
                event.flags.remove(flag)
            }
        }
        return event
    }

    private func handleModifierKeyAction(for event: CGEvent, action: Action) -> CGEvent? {
        let scrollWheelEventView = ScrollWheelEventView(event)

        switch action {
        case .auto, .ignore:
            break
        case .preventDefault:
            return nil
        case .alterOrientation:
            scrollWheelEventView.swapXY()
        case let .changeSpeed(scale: scale):
            scrollWheelEventView.scale(factor: scale.asTruncatedDouble)
        case .zoom, .zoomReversed:
            let scrollWheelEventView = ScrollWheelEventView(event)
            var deltaSignum = scrollWheelEventView.deltaYSignum != 0 ? scrollWheelEventView
                .deltaYSignum : scrollWheelEventView.deltaXSignum
            if action == .zoomReversed {
                deltaSignum *= -1
            }
            if deltaSignum == 0 {
                return event
            }
            let restoringModifierFlags = ModifierState.normalize(event.flags)
            if deltaSignum > 0 {
                try? keySimulator.press(
                    keys: [.numpadPlus],
                    modifierFlags: .maskCommand,
                    restoringModifierFlags: restoringModifierFlags,
                    tap: .cgSessionEventTap
                )
            } else {
                try? keySimulator.press(
                    keys: [.numpadMinus],
                    modifierFlags: .maskCommand,
                    restoringModifierFlags: restoringModifierFlags,
                    tap: .cgSessionEventTap
                )
            }
            return nil
        case .pinchZoom:
            pinchZoomReversed = false
            return handlePinchZoom(event, reverse: false)
        case .pinchZoomReversed:
            pinchZoomReversed = true
            return handlePinchZoom(event, reverse: true)
        }

        return event
    }

    private func handlePinchZoom(_ event: CGEvent, reverse: Bool) -> CGEvent? {
        guard event.type == .scrollWheel || event.type == .flagsChanged else {
            return event
        }

        if event.type == .flagsChanged {
            pinchZoomBegan = false
            pinchZoomReversed = false
            GestureEvent(zoomSource: nil, phase: .ended, magnification: 0)?.post(tap: .cgSessionEventTap)
            os_log("pinch zoom ended", log: Self.log, type: .info)
            return event
        }

        if !pinchZoomBegan {
            GestureEvent(zoomSource: nil, phase: .began, magnification: 0)?.post(tap: .cgSessionEventTap)
            pinchZoomBegan = true
            os_log("pinch zoom began", log: Self.log, type: .info)
        }

        let scrollWheelEventView = ScrollWheelEventView(event)
        let direction = reverse ? -1.0 : 1.0
        let magnification = Double(scrollWheelEventView.deltaYPt) * 0.005 * direction
        GestureEvent(zoomSource: nil, phase: .changed, magnification: magnification)?.post(tap: .cgSessionEventTap)
        os_log("pinch zoom changed: magnification=%f", log: Self.log, type: .info, magnification)

        return nil
    }
}

extension ModifierActionsTransformer: Deactivatable {
    func deactivate() {
        if pinchZoomBegan {
            pinchZoomBegan = false
            pinchZoomReversed = false
            GestureEvent(zoomSource: nil, phase: .ended, magnification: 0)?.post(tap: .cgSessionEventTap)
            os_log("ModifierActionsTransformer is inactive, pinch zoom ended", log: Self.log, type: .info)
        }
    }
}
