// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class EventTap {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTap")

    static let shared = EventTap()

    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        // TODO: Weak self reference?
        guard let unwrappedRefcon = refcon else {
            return Unmanaged.passUnretained(event)
        }

        let this = Unmanaged<EventTap>.fromOpaque(unwrappedRefcon).takeUnretainedValue()

        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        // FIXME: Avoid timeout?
        if type == .tapDisabledByTimeout {
            os_log("EventTap disabled by timeout, re-enable it", log: log, type: .error, String(describing: type))
            this.start()
            return Unmanaged.passUnretained(event)
        }

        let eventTransformer = EventTransformerManager.shared.get(withPid: MouseEventView(event).targetPid)

        if let event = eventTransformer.transform(event) {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }

    init() {
        guard AccessibilityPermission.enabled else {
            return
        }

        var eventsOfInterest: CGEventMask =
            1 << CGEventType.scrollWheel.rawValue
                | 1 << CGEventType.leftMouseDown.rawValue
                | 1 << CGEventType.leftMouseUp.rawValue
                | 1 << CGEventType.leftMouseDragged.rawValue
        eventsOfInterest |= 1 << CGEventType.rightMouseDown.rawValue
            | 1 << CGEventType.rightMouseUp.rawValue
            | 1 << CGEventType.rightMouseDragged.rawValue
        eventsOfInterest |= 1 << CGEventType.otherMouseDown.rawValue
            | 1 << CGEventType.otherMouseUp.rawValue
            | 1 << CGEventType.otherMouseDragged.rawValue
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

    func start() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }
}
