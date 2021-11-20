//
//  ModifierActions.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class ModifierActions: EventTransformer {
    private let appDefaults: AppDefaults
    private let mouseDetector: MouseDetector

    init(appDefaults: AppDefaults, mouseDetector: MouseDetector) {
        self.appDefaults = appDefaults
        self.mouseDetector = mouseDetector
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        guard mouseDetector.isMouseEvent(event) else {
            return event
        }

        let actions: [(CGEventFlags.Element, ModifierKeyAction)] = [
            (.maskCommand, appDefaults.modifiersCommandAction),
            (.maskShift, appDefaults.modifiersShiftAction),
            (.maskAlternate, appDefaults.modifiersAlternateAction),
            (.maskControl, appDefaults.modifiersControlAction),
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
