// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation
import ObservationToken
import os.log

enum EventTap {}

extension EventTap {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTap")

    typealias Callback = (_ proxy: CGEventTapProxy, _ event: CGEvent) -> CGEvent?

    private class ContextHolder {
        var tap: CFMachPort?
        let callback: Callback

        init(_ callback: @escaping Callback) {
            self.callback = callback
        }
    }

    private static let callbackInvoker: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
        // If no refcon (aka userInfo) is passed in, just bypass the event.
        guard let refcon = refcon else {
            return Unmanaged.passUnretained(event)
        }

        // Get the tap and the callback from contextHolder.
        let contextHolder = Unmanaged<ContextHolder>.fromOpaque(refcon).takeUnretainedValue()
        let tap = contextHolder.tap
        let callback = contextHolder.callback

        switch type {
        case .tapDisabledByUserInput:
            return Unmanaged.passUnretained(event)

        case .tapDisabledByTimeout:
            os_log("EventTap disabled by timeout, re-enable it", log: log, type: .error, String(describing: type))
            guard let tap = tap else {
                os_log("Cannot find the tap", log: log, type: .error, String(describing: type))
                return Unmanaged.passUnretained(event)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            return Unmanaged.passUnretained(event)

        default:
            // If the callback returns nil, ignore the event.
            guard let event = callback(proxy, event) else {
                return nil
            }

            // Or, return the event reference.
            return Unmanaged.passUnretained(event)
        }
    }

    /**
     Create an `EventTap` to observe the `events` and add it to the `runLoop`.

     - Parameters:
        - events: The event types to observe.
        - runLoop: The target `RunLoop` to run the event tap.
        - callback: The callback of the event tap.
     */
    static func observe(_ events: [CGEventType],
                        place: CGEventTapPlacement = .headInsertEventTap,
                        at runLoop: RunLoop = .current,
                        callback: @escaping Callback) throws -> ObservationToken {
        // Create a context holder. The lifetime of contextHolder should be the same as ObservationToken's.
        let contextHolder = ContextHolder(callback)

        // Create event tap.
        let eventsOfInterest = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: place,
                                          options: .defaultTap,
                                          eventsOfInterest: eventsOfInterest,
                                          callback: callbackInvoker,
                                          userInfo: Unmanaged.passUnretained(contextHolder).toOpaque()) else {
            throw EventTapError.failedToCreate
        }

        // Attach tap to contextHolder.
        contextHolder.tap = tap

        // Create and add run loop source to the run loop.
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let cfRunLoop = runLoop.getCFRunLoop()
        CFRunLoopAddSource(cfRunLoop, runLoopSource, .commonModes)

        return ObservationToken {
            // The lifetime of contextHolder needs to be extended until the observation token is cancelled.
            withExtendedLifetime(contextHolder) {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(cfRunLoop, runLoopSource, .commonModes)
                CFMachPortInvalidate(tap)
            }
        }
    }
}

enum EventTapError: Error {
    case failedToCreate
}
