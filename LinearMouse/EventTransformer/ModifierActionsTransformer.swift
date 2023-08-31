// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation
import KeyKit

class ModifierActionsTransformer: EventTransformer {
    typealias Modifiers = Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Modifiers>
    typealias Action = Scheme.Scrolling.Modifiers.Action

    private let modifiers: Modifiers

    init(modifiers: Modifiers) {
        self.modifiers = modifiers
    }

    func transform(_ event: CGEvent) -> CGEvent? {
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
        }

        return event
    }
}
