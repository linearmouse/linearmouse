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

    private let defaultMouseDetector = DefaultMouseDetector()
    private let experimentalMouseDetector = ExperimentalMouseDetector()
    private var mouseDetector: MouseDetector {
        AppDefaults.shared.experimentalMouseDetector ? experimentalMouseDetector : defaultMouseDetector
    }

    let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // TODO: Weak self reference?
        guard let unwrappedRefcon = refcon else {
            return Unmanaged.passUnretained(event)
        }
        let this = Unmanaged<EventTap>.fromOpaque(unwrappedRefcon).takeUnretainedValue()
        if let event = transformEvent(appDefaults: AppDefaults.shared, mouseDetector: this.mouseDetector, event: event) {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    init() {
        let eventsOfInterest: CGEventMask =
            1 << CGEventType.scrollWheel.rawValue
            | 1 << CGEventType.otherMouseDown.rawValue
            | 1 << CGEventType.otherMouseUp.rawValue
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
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
