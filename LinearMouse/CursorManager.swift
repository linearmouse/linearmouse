//
//  CursorManager.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/12/9.
//

import Foundation
import IOKit
import os.log

/**
 Configures mouse acceleration and sensitivity.

 Greatly inspired by [mac-mouse-fix](https://github.com/noah-nuebling/mac-mouse-fix/blob/7a52439679ab242a891d0071443512b23f73dbe4/Helper/Pointer/PointerSpeed.m#L33).
 */
class CursorManager {
    static var shared = CursorManager()

    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "CursorManager")
    static let defaultAcceleration = Double(0.6875)
    static let defaultSensitivity = Int(1600)

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

    private let client: IOHIDEventSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault).takeRetainedValue()
    private var services = Set<IOHIDServiceClient>()
    private var timer: Timer?

    init() {
        let match = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
        ]
        IOHIDEventSystemClientSetMatching(client, match as CFDictionary)
        IOHIDEventSystemClientRegisterDeviceMatchingBlock(client, { _, _, service in
            if let service = service {
                self.add(service: service)
            }
        }, nil, nil)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return
        }
        for service in services {
            add(service: service)
        }
        IOHIDEventSystemClientScheduleWithDispatchQueue(client, DispatchQueue.main)
    }

    deinit {
        stop()
        IOHIDEventSystemClientUnregisterDeviceMatchingBlock(client)
    }

    private func add(service: IOHIDServiceClient) {
        if services.contains(service) {
            return
        }
        guard let productRef = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) else {
            return
        }
        guard let product = productRef as? String else {
            return
        }
        IOHIDServiceClientRegisterRemovalBlock(service, { _, _, _ in
            self.services.remove(service)
            os_log("device removed: %{public}@", log: Self.log, type: .debug, product)
        }, nil, nil)
        services.insert(service)
        os_log("device added: %{public}@", log: Self.log, type: .debug, product)
        update()
    }

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

    func update() {
        guard timer != nil else {
            return
        }
        for service in services {
            guard let productRef = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) else {
                continue
            }
            guard let product = productRef as? String else {
                continue
            }
            guard let _ = IOHIDServiceClientCopyProperty(service, kIOHIDMouseAccelerationTypeKey as CFString) else {
                os_log("%{public}@ is skipped as it might be a trackpad", log: Self.log, type: .debug, product)
                continue
            }
            os_log("updating sensitivity and acceleration for %{public}@", log: Self.log, type: .debug, product)
            var value = resolutionValue
            IOHIDServiceClientSetProperty(
                service, kIOHIDPointerResolutionKey as CFString,
                CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &value))
            // Resolution changes would not take effect before some other mouse settings change.
            // So I put the acceleration changes below.
            value = accelerationValue
            IOHIDServiceClientSetProperty(
                service, kIOHIDMouseAccelerationTypeKey as CFString,
                CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &value))
        }
    }

    func revertToSystemDefaults() {
        disableAccelerationAndSensitivity = false
        acceleration = Self.defaultAcceleration
        sensitivity = Self.defaultSensitivity
        update()
    }
}
