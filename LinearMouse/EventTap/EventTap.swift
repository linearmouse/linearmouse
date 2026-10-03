// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import ObservationToken
import os.log

enum EventTap {}

extension EventTap {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTap")

    typealias Callback = (_ proxy: CGEventTapProxy, _ event: CGEvent) -> CGEvent?

    /// Access only on the tap's run loop. Deliberately disabled taps must stay
    /// disabled when the watchdog or a timeout notification runs.
    final class Control {
        fileprivate var tap: CFMachPort?
        var isEnabled: Bool {
            didSet {
                guard oldValue != isEnabled, let tap else {
                    return
                }
                CGEvent.tapEnable(tap: tap, enable: isEnabled)
            }
        }

        init(isEnabled: Bool = true) {
            self.isEnabled = isEnabled
        }
    }

    private class ContextHolder {
        let control: Control
        let callback: Callback

        init(_ callback: @escaping Callback, control: Control) {
            self.callback = callback
            self.control = control
        }
    }

    private static let callbackInvoker: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
        // If no refcon (aka userInfo) is passed in, just bypass the event.
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        // Get the tap and the callback from contextHolder.
        let contextHolder = Unmanaged<ContextHolder>.fromOpaque(refcon).takeUnretainedValue()
        let tap = contextHolder.control.tap
        let callback = contextHolder.callback

        switch type {
        case .tapDisabledByUserInput:
            return Unmanaged.passUnretained(event)

        case .tapDisabledByTimeout:
            os_log("EventTap disabled by timeout, re-enable it", log: log, type: .error, String(describing: type))
            guard let tap else {
                os_log("Cannot find the tap", log: log, type: .error, String(describing: type))
                return Unmanaged.passUnretained(event)
            }
            CGEvent.tapEnable(tap: tap, enable: contextHolder.control.isEnabled)
            return Unmanaged.passUnretained(event)

        default:
            let originalEvent = event

            // If the callback returns nil, ignore the event.
            guard let event = callback(proxy, event) else {
                return nil
            }

            // If the callback returns a different event (e.g. a copy),
            // use passRetained to transfer ownership to the caller.
            if event === originalEvent {
                return Unmanaged.passUnretained(event)
            }
            return Unmanaged.passRetained(event)
        }
    }

    /**
     Create an `EventTap` to observe the `events` and add it to the `runLoop`.

     - Parameters:
        - events: The event types to observe.
        - runLoop: The target `RunLoop` to run the event tap.
        - callback: The callback of the event tap.
     */
    static func observe(
        _ events: [CGEventType],
        place: CGEventTapPlacement = .headInsertEventTap,
        at runLoop: RunLoop = .current,
        onInvalidated: (() -> Void)? = nil,
        control: Control = Control(),
        callback: @escaping Callback
    ) throws -> ObservationToken {
        // Create a context holder. The lifetime of contextHolder should be the same as ObservationToken's.
        let contextHolder = ContextHolder(callback, control: control)

        // Create event tap.
        let eventsOfInterest = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: place,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: callbackInvoker,
            userInfo: Unmanaged.passUnretained(contextHolder).toOpaque()
        ) else {
            throw EventTapError.failedToCreate
        }

        // Attach tap to contextHolder.
        control.tap = tap
        CGEvent.tapEnable(tap: tap, enable: control.isEnabled)

        // Create and add run loop source to the run loop.
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let cfRunLoop = runLoop.getCFRunLoop()
        CFRunLoopAddSource(cfRunLoop, runLoopSource, .commonModes)

        // Periodically check if the tap is still enabled and re-enable it if needed.
        // This recovers from cases where the system silently disables the tap
        // (e.g. due to an invalid event or other transient errors).
        var didNotifyInvalidation = false
        let healthCheckTimer = Timer(timeInterval: 5, repeats: true) { _ in
            guard CFMachPortIsValid(tap) else {
                guard !didNotifyInvalidation else {
                    return
                }
                didNotifyInvalidation = true
                os_log("EventTap became invalid", log: log, type: .error)
                onInvalidated?()
                return
            }
            if control.isEnabled, !CGEvent.tapIsEnabled(tap: tap) {
                os_log("EventTap found disabled, re-enabling", log: log, type: .error)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        runLoop.add(healthCheckTimer, forMode: .common)

        return ObservationToken {
            // The lifetime of contextHolder needs to be extended until the observation token is cancelled.
            CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) {
                healthCheckTimer.invalidate()
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(cfRunLoop, runLoopSource, .commonModes)
                CFMachPortInvalidate(tap)
                control.tap = nil
                withExtendedLifetime(contextHolder) {}
            }
            CFRunLoopWakeUp(cfRunLoop)
        }
    }
}

enum EventTapError: Error {
    case failedToCreate
}
