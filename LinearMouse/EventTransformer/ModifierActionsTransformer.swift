// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation

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
            if let action = action, action != .none {
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
        case .none:
            break
        case .alterOrientation:
            scrollWheelEventView.swapXY()
        case let .changeSpeed(scale: scale):
            scrollWheelEventView.scale(factor: scale.asTruncatedDouble)
        case .zoom:
            let scrollWheelEventView = ScrollWheelEventView(event)
            // TODO: Extract a KeyboardKit?
            CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true)?.post(tap: .cgSessionEventTap)
            let deltaSignum = scrollWheelEventView.deltaYSignum != 0 ? scrollWheelEventView
                .deltaYSignum : scrollWheelEventView.deltaXSignum
            if deltaSignum == 0 {
                return event
            }
            let virtualKey: CGKeyCode = deltaSignum > 0 ? 0x45 : 0x4E
            if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true) {
                keyDownEvent.flags = .maskCommand
                keyDownEvent.post(tap: .cgSessionEventTap)
            }
            if let keyDownUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) {
                keyDownUp.flags = .maskCommand
                keyDownUp.post(tap: .cgSessionEventTap)
            }
            CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false)?.post(tap: .cgSessionEventTap)
            return nil
        }

        return event
    }
}
