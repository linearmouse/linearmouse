// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

class ModifierActions: EventTransformer {
    typealias Modifiers = Scheme.Scrolling.Modifiers

    private let modifiers: Modifiers

    init(modifiers: Scheme.Scrolling.Modifiers) {
        self.modifiers = modifiers
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let actions: [(CGEventFlags.Element, Modifiers.Action?)] = [
            (.maskCommand, modifiers.command),
            (.maskShift, modifiers.shift),
            (.maskAlternate, modifiers.option),
            (.maskControl, modifiers.control)
        ]
        for case let (flag, action) in actions {
            if event.flags.contains(flag) {
                if handleModifierKeyAction(for: event, action: action) {
                    event.flags.remove(flag)
                }
            }
        }
        return event
    }

    private func handleModifierKeyAction(for event: CGEvent, action: Modifiers.Action?) -> Bool {
        guard let action = action else {
            return false
        }

        let view = ScrollWheelEventView(event)

        switch action {
        case .none:
            return false
        case .alterOrientation:
            view.swapXY()
        case let .changeSpeed(scale: scale):
            view.scale(factor: scale.asTruncatedDouble)
        }

        return true
    }
}
