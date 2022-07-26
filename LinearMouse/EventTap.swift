// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log

class EventTap {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTap")

    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    private let mouseDetector = DefaultMouseDetector()

    private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        // TODO: Weak self reference?
        guard let unwrappedRefcon = refcon else {
            return Unmanaged.passUnretained(event)
        }

        let this = Unmanaged<EventTap>.fromOpaque(unwrappedRefcon).takeUnretainedValue()

        // FIXME: Avoid timeout?
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            os_log("EventTap disabled (%{public}@), re-enable it", log: log, type: .error, String(describing: type))
            this.enable()
        }

        if let event = transformEvent(event) {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }

    init() {
        let eventsOfInterest: CGEventMask =
            1 << CGEventType.scrollWheel.rawValue
                | 1 << CGEventType.leftMouseDown.rawValue
                | 1 << CGEventType.leftMouseUp.rawValue
                | 1 << CGEventType.rightMouseDown.rawValue
                | 1 << CGEventType.rightMouseUp.rawValue
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
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
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
