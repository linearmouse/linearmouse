//
//  MouseWheelEvent.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/8/1.
//

import Foundation

class MouseWheelEvent {
    let event: CGEvent

    let defaults = AppDefaults.shared

    var continuous: Bool {
        get { event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 }
        set { event.setIntegerValueField(.scrollWheelEventIsContinuous, value: newValue ? 1 : 0) }
    }

    var deltaX: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis2) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: newValue) }
    }

    var deltaY: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis1) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: newValue) }
    }

    init(_ event: CGEvent) {
        self.event = event
    }

    lazy var transformed: CGEvent = {
        guard !continuous else {
            return event
        }

        if defaults.reverseScrollingOn {
            negateDelta()
        }

        if defaults.linearScrollingOn {
            let scrollLines = Int64(defaults.scrollLines)
            deltaX = deltaX.signum() * scrollLines
            deltaY = deltaY.signum() * scrollLines
        }

        modifierActions()

        return event
    }()

    func negateDelta() {
        deltaX = -deltaX
        deltaY = -deltaY
    }

    func modifierActions() {
        let actions: [(CGEventFlags.Element, ModifierKeyAction)] = [
            (.maskCommand, defaults.modifiersCommandAction),
            (.maskShift, defaults.modifiersShiftAction),
            (.maskAlternate, defaults.modifiersAlternateAction),
            (.maskControl, defaults.modifiersControlAction),
        ]
        for case (let flag, let action) in actions {
            if event.flags.contains(flag) {
                if handleModifierKeyAction(for: event, action: action) {
                    event.flags.remove(flag)
                }
            }
        }
    }

    func handleModifierKeyAction(for event: CGEvent, action: ModifierKeyAction) -> Bool {
        guard action.type != .noAction else {
            return false
        }

        // fix orientation on Catalina
        // TODO: is there a better way?
        if deltaY == 0 {
            (deltaX, deltaY) = (deltaY, deltaX)
        }

        switch action.type {
        case .noAction: // make the compiler happy
            break
        case .alterOrientation:
            (deltaX, deltaY) = (deltaY, deltaX)
        case .changeSpeed:
            let factor = action.speedFactor
            let scale = { (delta: Int64, factor: Double) in Int64((Double(delta) * factor).rounded()) }
            deltaX = deltaX.signum() * max(1, abs(scale(deltaX, factor)))
            deltaY = deltaY.signum() * max(1, abs(scale(deltaY, factor)))
        }

        return true
    }
}
