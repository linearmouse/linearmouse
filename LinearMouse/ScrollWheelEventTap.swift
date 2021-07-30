//
//  ScrollWheelEventTap.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/11.
//

import Foundation

class ScrollWheelEventTap {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    let scrollEventCallback: CGEventTapCallBack = { (proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon) in
        let defaults = AppDefaults.shared
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        // trackpad events are continuous and we simply ignore them
        if isContinuous == 0 {
            if defaults.reverseScrollingOn {
                event.setIntegerValueField(
                    .scrollWheelEventDeltaAxis1,
                    value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                )
                event.setIntegerValueField(
                    .scrollWheelEventDeltaAxis2,
                    value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                )
            }
            if defaults.linearScrollingOn {
                event.setIntegerValueField(
                    .scrollWheelEventDeltaAxis1,
                    value: event.getIntegerValueField(.scrollWheelEventDeltaAxis1).signum() * Int64(defaults.scrollLines)
                )
                event.setIntegerValueField(
                    .scrollWheelEventDeltaAxis2,
                    value: event.getIntegerValueField(.scrollWheelEventDeltaAxis2).signum() * Int64(defaults.scrollLines)
                )
            }
            let modifierActions: [(CGEventFlags.Element, ModifierKeyAction)] = [
                (.maskCommand, defaults.modifiersCommandAction),
                (.maskShift, defaults.modifiersShiftAction),
                (.maskAlternate, defaults.modifiersAlternateAction),
                (.maskControl, defaults.modifiersControlAction),
            ]
            for case (let flag, let action) in modifierActions {
                if event.flags.contains(flag) {
                    if handleModifierKeyAction(for: event, action: action) {
                        event.flags.remove(flag)
                    }
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    init() {
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: scrollEventCallback,
            userInfo: nil
        )
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
        CFRunLoopRun()
    }

    func enable() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func disable() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    static func handleModifierKeyAction(for event: CGEvent, action: ModifierKeyAction) -> Bool {
        guard action.type != .noAction else { return false }
        // fix orientation on Catalina
        // TODO: is there a better way?
        if event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0 {
            alterOrientation(for: event)
        }
        switch action.type {
        case .noAction: // make the compiler happy
            break
        case .alterOrientation:
            alterOrientation(for: event)
        case .changeSpeed:
            changeSpeed(for: event, factor: action.speedFactor)
        }
        return true
    }

    static func alterOrientation(for event: CGEvent) {
        let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: axis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: axis1)
    }

    static func changeSpeed(for event: CGEvent, factor: Double) {
        var axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        var axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        axis1 = axis1.signum() * max(1, abs(Int64((Double(axis1) * factor).rounded())))
        axis2 = axis2.signum() * max(1, abs(Int64((Double(axis2) * factor).rounded())))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: axis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: axis2)
    }
}
