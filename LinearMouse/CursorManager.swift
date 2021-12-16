//
//  CursorManager.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/12/9.
//

import Foundation
import IOKit
import os

typealias IOHIDEventSystemClientCreate = @convention(c) (_ allocator: CFAllocator?) -> IOHIDEventSystemClient
typealias IOHIDEventSystemClientSetMatching = @convention(c) (
    _ client: IOHIDEventSystemClient?, _ matches: CFDictionary?
) -> Void

let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", 2)
let eventSystemClientCreate = unsafeBitCast(
    dlsym(handle, "IOHIDEventSystemClientCreate"), to: IOHIDEventSystemClientCreate.self)
let eventSystemClientSetMatching = unsafeBitCast(
    dlsym(handle, "IOHIDEventSystemClientSetMatching"), to: IOHIDEventSystemClientSetMatching.self)

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CursorManager")

let defaultAcceleration = Double(0.6875)
let defaultSensitivity = Int(1600)

/**
 Configures mouse acceleration and sensitivity.

 Greatly inspired by [mac-mouse-fix](https://github.com/noah-nuebling/mac-mouse-fix/blob/7a52439679ab242a891d0071443512b23f73dbe4/Helper/Pointer/PointerSpeed.m#L33).
 */
class CursorManager {
    static var shared = CursorManager()

    private let client: IOHIDEventSystemClient = eventSystemClientCreate(kCFAllocatorDefault)

    var disableAccelerationAndSensitivity = false

    private var _acceleration = defaultAcceleration
    var acceleration: Double {
        set { _acceleration = max(0, min(newValue, 20)) }
        get { return _acceleration }
    }
    private var accelerationValue: Int { disableAccelerationAndSensitivity ? -65536 : Int(_acceleration * 65536) }

    private var _sensitivity = defaultSensitivity
    var sensitivity: Int {
        set { _sensitivity = max(5, min(newValue, 1990)) }
        get { return _sensitivity }
    }
    private var resolutionValue: Int { (2000 - _sensitivity) << 16 }

    private var timer: Timer?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            self.update()
        }
        self.update()
    }

    func stop() {
        if let timer = timer {
            self.timer = nil
            timer.invalidate()
        }
    }

    deinit {
        stop()
    }

    func update() {
        let match = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
        ]
        eventSystemClientSetMatching(client, match as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return
        }
        for service in services {
            guard let productRef = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) else {
                continue
            }
            guard let product = productRef as? String else {
                continue
            }
            guard let accelerationKeyRef = IOHIDServiceClientCopyProperty(service, kIOHIDPointerAccelerationTypeKey as CFString) else {
                logger.debug("[skip] \(product, privacy: .public) is skipped as kIOHIDPointerAccelerationTypeKey is not found")
                continue
            }
            guard let accelerationKey = accelerationKeyRef as? String else {
                logger.debug("[skip] \(product, privacy: .public) is skipped as kIOHIDPointerAccelerationTypeKey is not a String")
                continue
            }
            guard IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) == 0 else {
                logger.debug("[skip] \(product, privacy: .public) is skipped as it reports itself as a trackpad")
                continue
            }
            logger.debug("[update] updating sensitivity and acceleration for \(product, privacy: .public)")
            var value = resolutionValue
            IOHIDServiceClientSetProperty(
                service, kIOHIDPointerResolutionKey as CFString,
                CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &value))
            // Resolution changes would not take effect before some other mouse settings change.
            // So I put the acceleration changes below.
            value = accelerationValue
            IOHIDServiceClientSetProperty(
                service, accelerationKey as CFString,
                CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &value))
        }
    }

    func revertToSystemDefaults() {
        disableAccelerationAndSensitivity = false
        acceleration = defaultAcceleration
        sensitivity = defaultSensitivity
        update()
    }
}
