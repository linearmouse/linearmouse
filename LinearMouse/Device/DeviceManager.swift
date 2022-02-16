//
//  DeviceManager.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/14.
//

import Foundation
import os.log

class DeviceManager {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")

    private let eventSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault).takeRetainedValue()
    private var devices = Set<Device>()

    private let propertyChangedCallback: IOHIDEventSystemClientPropertyChangedCallback = { target, _, property, value in
        let this = Unmanaged<DeviceManager>.fromOpaque(target!).takeUnretainedValue()
        this.propertyChangedCallback(property! as String, value)
    }

    private var lastPointerAcceleration: Double?
    private var lastPointerSensitivity: Int?
    private var lastDisablePointerAcceleration: Bool?

    private weak var _lastActiveDevice: Device?
    weak var lastActiveDevice: Device? { _lastActiveDevice }

    init() {
        setupServiceClients()
        setupPropertyChangedCallback()
        setupActiveDeviceChangedCallback()
        IOHIDEventSystemClientScheduleWithDispatchQueue(eventSystemClient, DispatchQueue.main)
    }

    private func setupServiceClients() {
        let usageMouse = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ] as CFDictionary
        let usagePointer = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer
        ] as CFDictionary
        let matches = [usageMouse, usagePointer] as CFArray
        IOHIDEventSystemClientSetMatchingMultiple(eventSystemClient, matches)
        IOHIDEventSystemClientRegisterDeviceMatchingBlock(eventSystemClient, { _, _, serviceClient in
            DispatchQueue.main.async {
                if let serviceClient = serviceClient {
                    if let device = self.add(serviceClient: serviceClient) {
                        self.renewPointerSpeed(forDevice: device)
                    }
                }
            }
        }, nil, nil)
        let serviceClients = IOHIDEventSystemClientCopyServices(eventSystemClient) as! [IOHIDServiceClient]
        for serviceClient in serviceClients {
            add(serviceClient: serviceClient)
        }
    }

    private func setupPropertyChangedCallback() {
        for property in [kIOHIDMouseAccelerationType, kIOHIDTrackpadAccelerationType, kIOHIDPointerResolutionKey] {
            IOHIDEventSystemClientRegisterPropertyChangedCallback(eventSystemClient,
                                                                  property as CFString,
                                                                  propertyChangedCallback,
                                                                  Unmanaged.passUnretained(self).toOpaque(),
                                                                  nil)
        }
    }

    @discardableResult
    private func add(serviceClient: IOHIDServiceClient) -> Device? {
        guard !devices.contains(where: { $0.serviceClientEquals(serviceClient: serviceClient) }) else {
            return nil
        }
        guard let device = Device(serviceClient: serviceClient) else {
            os_log("Unsupported device: %{public}@", log: Self.log, type: .debug, String(describing: serviceClient))
            return nil
        }
        IOHIDServiceClientRegisterRemovalBlock(serviceClient, { _, _, _ in
            DispatchQueue.main.async {
                self.devices.remove(device)
                os_log("Device removed: %{public}@", log: Self.log, type: .debug, String(describing: device))
            }
        }, nil, nil)
        devices.insert(device)
        os_log("Device added: %{public}@", log: Self.log, type: .debug, String(describing: device))
        return device
    }

    private func propertyChangedCallback(_ property: String, _ value: AnyObject?) {
        let valueDesc = value == nil ? "<nil>" : String(describing: value!)
        os_log("Property %@ changed to %@", log: Self.log, type: .debug, property, valueDesc)
        DispatchQueue.main.async {
            self.renewPointerSpeed()
        }
    }

    private func shouldIgnoreSpeedSettings(forDevice device: Device) -> Bool {
        guard device.category == .mouse else {
            os_log("Device ignored for speed settings: %@: Category is %@", log: Self.log, type: .debug,
                   String(describing: device), String(describing: device.category))
            return true
        }
        return false
    }

    func updatePointerSpeed(acceleration: Double, sensitivity: Int, disableAcceleration: Bool) {
        lastPointerAcceleration = acceleration
        lastPointerSensitivity = sensitivity
        lastDisablePointerAcceleration = disableAcceleration
        for device in devices {
            guard !shouldIgnoreSpeedSettings(forDevice: device) else {
                continue
            }
            device.updatePointerSpeed(acceleration: acceleration, sensitivity: sensitivity, disableAcceleration: disableAcceleration)
        }
    }

    func renewPointerSpeed() {
        if let acceleration = lastPointerAcceleration,
           let sensitivity = lastPointerSensitivity,
           let disableAcceleration = lastDisablePointerAcceleration {
            updatePointerSpeed(acceleration: acceleration, sensitivity: sensitivity, disableAcceleration: disableAcceleration)
        }
    }

    func renewPointerSpeed(forDevice device: Device) {
        if let acceleration = lastPointerAcceleration,
           let sensitivity = lastPointerSensitivity,
           let disableAcceleration = lastDisablePointerAcceleration {
            device.updatePointerSpeed(acceleration: acceleration, sensitivity: sensitivity, disableAcceleration: disableAcceleration)
        }
    }

    func restorePointerSpeedToInitialValue() {
        for device in devices {
            guard !shouldIgnoreSpeedSettings(forDevice: device) else {
                continue
            }
            device.restorePointerSpeedToInitialValue()
        }
    }

    private var firstAvailableDevice: Device? {
        devices.first { !shouldIgnoreSpeedSettings(forDevice: $0) }
    }

    var pointerAcceleration: Double {
        firstAvailableDevice?.pointerAcceleration ?? 0.6875
    }

    var pointerSensitivity: Int {
        firstAvailableDevice?.pointerSensitivity ?? 1600
    }

    func getSystemProperty<T>(forKey key: String) -> T? {
        let service = IORegistryEntryFromPath(kIOMasterPortDefault, "\(kIOServicePlane):/IOResources/IOHIDSystem")
        guard service != .zero else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var handle: io_connect_t = .zero
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &handle) == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(handle) }

        var valueRef: Unmanaged<CFTypeRef>?
        guard IOHIDCopyCFTypeParameter(handle, key as CFString, &valueRef) == KERN_SUCCESS else {
            return nil
        }
        guard let valueRefUnwrapped = valueRef else {
            return nil
        }
        guard let value = valueRefUnwrapped.takeRetainedValue() as? T else {
            return nil
        }
        return value
    }

    private func setupActiveDeviceChangedCallback() {
        // TODO: Use IOHIDDeviceRegisterInputReportCallback?
        IOHIDEventSystemClientRegisterEventBlock(eventSystemClient, { _, _, sender, event in
            guard let serviceClient = sender else {
                return
            }
            if let lastActiveDevice = self._lastActiveDevice {
                if lastActiveDevice.serviceClientEquals(serviceClient: serviceClient) {
                    return
                }
            }
            if let device = self.devices.first(where: { $0.serviceClientEquals(serviceClient: serviceClient) }) {
                self._lastActiveDevice = device
                os_log("Last active device changed: %{public}@, Category=%{public}@",
                       log: Self.log, type: .debug,
                       String(describing: device), String(describing: device.category))
            }
        }, nil, nil)
    }
}
