//
//  ScrollWheelEventTap.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/11.
//

import Foundation

class ScrollWheelEventTap {
    static let mouseScrollLines = Int64(3)

    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    let scrollEventCallback: CGEventTapCallBack = { (proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon) in
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        // trackpad events are continuous and we simply ignore them
        if isContinuous == 0 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: event.getIntegerValueField(.scrollWheelEventDeltaAxis1).signum() * mouseScrollLines)
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
}
