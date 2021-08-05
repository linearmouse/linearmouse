//
//  ScrollWheelEventTap.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/11.
//

import Foundation

class EventTap {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
        if let transformed: CGEvent = {
            switch type {
            case .scrollWheel:
                return MouseWheelEvent(event).transformed
            case .otherMouseUp:
                return fixSideButtonsEvent(event)
            default:
                return event
            }
        }() {
            return Unmanaged.passUnretained(transformed)
        }
        return nil
    }

    init() {
        let eventsOfInterest: CGEventMask =
            1 << CGEventType.scrollWheel.rawValue
            | 1 << CGEventType.otherMouseUp.rawValue
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: eventTapCallback,
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
}
