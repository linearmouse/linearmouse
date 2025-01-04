// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation
import GestureKit
import KeyKit
import os.log

class ModifierActionsTransformer {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ModifierActionsTransformer"
    )

    typealias Modifiers = Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Modifiers>
    typealias Action = Scheme.Scrolling.Modifiers.Action

    private let modifiers: Modifiers

    private var pinchZoomBegan = false

    init(modifiers: Modifiers) {
        self.modifiers = modifiers
    }
}

extension ModifierActionsTransformer: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        if pinchZoomBegan {
            return handlePinchZoom(event)
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
            if let action = action, action != .auto {
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
        case .zoom:
            let scrollWheelEventView = ScrollWheelEventView(event)
            let deltaSignum = scrollWheelEventView.deltaYSignum != 0 ? scrollWheelEventView
                .deltaYSignum : scrollWheelEventView.deltaXSignum
            if deltaSignum == 0 {
                return event
            }
            let keySimulator = KeySimulator()
            if deltaSignum > 0 {
                try? keySimulator.press(.command, .numpadPlus, tap: .cgSessionEventTap)
            } else {
                try? keySimulator.press(.command, .numpadMinus, tap: .cgSessionEventTap)
            }
            return nil
        case .pinchZoom:
            return handlePinchZoom(event)
        }

        return event
    }

    private func handlePinchZoom(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel || event.type == .flagsChanged else {
            return event
        }

        if event.type == .flagsChanged {
            pinchZoomBegan = false
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
        let magnification = Double(scrollWheelEventView.deltaYPt) * 0.005
        GestureEvent(zoomSource: nil, phase: .changed, magnification: magnification)?.post(tap: .cgSessionEventTap)
        os_log("pinch zoom changed: magnification=%f", log: Self.log, type: .info, magnification)

        return nil
    }
}

extension ModifierActionsTransformer: Deactivatable {
    func deactivate() {
        if pinchZoomBegan {
            pinchZoomBegan = false
            GestureEvent(zoomSource: nil, phase: .ended, magnification: 0)?.post(tap: .cgSessionEventTap)
            os_log("ModifierActionsTransformer is inactive, pinch zoom ended", log: Self.log, type: .info)
        }
    }
}
