//
//  DeviceManager.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/14.
//

import Foundation
import os.log
import PointerKit

class DeviceManager {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")

    private let manager = PointerDeviceManager()
    private var devices = Set<Device>()

    private var lastPointerAcceleration: Double?
    private var lastPointerSensitivity: Double?
    private var lastDisablePointerAcceleration: Bool?

    weak var _lastActiveDevice: Device?
    weak var lastActiveDevice: Device? { _lastActiveDevice }

    init() {
        manager.observeDeviceAdded(using: deviceAdded).tieToLifetime(of: self)
        manager.observeDeviceRemoved(using: deviceRemoved).tieToLifetime(of: self)

        for property in [kIOHIDMouseAccelerationType, kIOHIDTrackpadAccelerationType, kIOHIDPointerResolutionKey] {
            manager.observePropertyChanged(property: property) { [self] _ in
                os_log("Property %@ changed", log: Self.log, type: .debug, property)
                renewPointerSpeed()
            }.tieToLifetime(of: self)
        }

        resume()
    }

    func pause() {
        restorePointerSpeedToInitialValue()
        manager.stopObservation()
    }

    func resume() {
        manager.startObservation()
        renewPointerSpeed()
    }

    private func deviceAdded(_: PointerDeviceManager, device: PointerDevice) {
        guard let device = Device(self, device) else {
            os_log("Unsupported device: %{public}@",
                   log: Self.log, type: .debug,
                   String(describing: device))
            return
        }

        devices.insert(device)

        os_log("Device added: %{public}@",
               log: Self.log, type: .debug,
               String(describing: device))

        renewPointerSpeed(forDevice: device)
    }

    private func deviceRemoved(_: PointerDeviceManager, device: PointerDevice) {
        // TODO: Better approach?

        devices.filter { $0.device == device }
            .forEach { devices.remove($0) }

        os_log("Device removed: %{public}@",
               log: Self.log, type: .debug,
               String(describing: device))
    }

    func updatePointerSpeed(acceleration: Double, sensitivity: Double, disableAcceleration: Bool) {
        lastPointerAcceleration = acceleration
        lastPointerSensitivity = sensitivity
        lastDisablePointerAcceleration = disableAcceleration
        for device in devices {
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
            device.restorePointerSpeedToInitialValue()
        }
    }

    private var firstAvailableDevice: Device? {
        devices.first { $0.shouldApplyPointerSpeedSettings }
    }

    var pointerAcceleration: Double {
        firstAvailableDevice?.pointerAcceleration ?? 0.6875
    }

    var pointerSensitivity: Double {
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

//    private func setupActiveDeviceChangedCallback() {
//        // TODO: Use IOHIDDeviceRegisterInputReportCallback?
//        IOHIDEventSystemClientRegisterEventBlock(eventSystemClient, { _, _, sender, event in
//            guard let serviceClient = sender else {
//                return
//            }
//            if let lastActiveDevice = self._lastActiveDevice {
//                if lastActiveDevice.serviceClientEquals(serviceClient: serviceClient) {
//                    return
//                }
//            }
//            if let device = self.devices.first(where: { $0.serviceClientEquals(serviceClient: serviceClient) }) {
//                self._lastActiveDevice = device
//                os_log("Last active device changed: %{public}@, Category=%{public}@",
//                       log: Self.log, type: .debug,
//                       String(describing: device), String(describing: device.category))
//            }
//        }, nil, nil)
//    }
}
