// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

class ModifierActions: EventTransformer {
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
        for case let (flag, action) in actions where event.flags.contains(flag) {
            if let action = action {
                if handleModifierKeyAction(for: event, action: action) {
                    event.flags.remove(flag)
                }
            }
        }
        return event
    }

    private func handleModifierKeyAction(for event: CGEvent, action: Action) -> Bool {
        let scrollWheelEventView = ScrollWheelEventView(event)

        switch action {
        case .none:
            return false
        case .alterOrientation:
            scrollWheelEventView.swapXY()
        case let .changeSpeed(scale: scale):
            scrollWheelEventView.scale(factor: scale.asTruncatedDouble)
        }

        return true
    }
}
