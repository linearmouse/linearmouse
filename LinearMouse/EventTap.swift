// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

class EventTap {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    private let mouseDetector = DefaultMouseDetector()

    private let eventTapCallback: CGEventTapCallBack = { _, _, event, refcon in
        // TODO: Weak self reference?
        guard let unwrappedRefcon = refcon else {
            return Unmanaged.passUnretained(event)
        }
        let this = Unmanaged<EventTap>.fromOpaque(unwrappedRefcon).takeUnretainedValue()
        if let event = transformEvent(appDefaults: AppDefaults.shared, mouseDetector: this.mouseDetector,
                                      event: event) {
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
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
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
