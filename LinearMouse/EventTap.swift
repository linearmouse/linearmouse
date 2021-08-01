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
        return Unmanaged.passUnretained(MouseWheelEvent(event).transformed)
    }

    init() {
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
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
