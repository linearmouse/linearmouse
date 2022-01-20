//
//  ModifierActions.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class ModifierActions: EventTransformer {
    private let commandAction: ModifierKeyAction
    private let shiftAction: ModifierKeyAction
    private let alternateAction: ModifierKeyAction
    private let controlAction: ModifierKeyAction

    init(commandAction: ModifierKeyAction, shiftAction: ModifierKeyAction,
         alternateAction: ModifierKeyAction, controlAction: ModifierKeyAction) {
        self.commandAction = commandAction
        self.shiftAction = shiftAction
        self.alternateAction = alternateAction
        self.controlAction = controlAction
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let actions: [(CGEventFlags.Element, ModifierKeyAction)] = [
            (.maskCommand, commandAction),
            (.maskShift, shiftAction),
            (.maskAlternate, alternateAction),
            (.maskControl, controlAction),
        ]
        for case (let flag, let action) in actions {
            if event.flags.contains(flag) {
                if handleModifierKeyAction(for: event, action: action) {
                    event.flags.remove(flag)
                }
            }
        }
        return event
    }

    func handleModifierKeyAction(for event: CGEvent, action: ModifierKeyAction) -> Bool {
        let view = ScrollWheelEventView(event)

        switch action.type {
        case .noAction:
            return false
        case .alterOrientation:
            view.swapDeltaXY()
        case .changeSpeed:
            let factor = action.speedFactor
            let scale = { (delta: Int64, factor: Double) in Int64((Double(delta) * factor).rounded()) }
            view.deltaX = view.deltaX.signum() * max(1, abs(scale(view.deltaX, factor)))
            view.deltaY = view.deltaY.signum() * max(1, abs(scale(view.deltaY, factor)))
        }

        return true
    }
}
