// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log
import PointerKit

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")

    private let manager = PointerDeviceManager()

    private var pointerDeviceToDevice = [PointerDevice: Device]()
    private var devices: [Device] {
        Array(pointerDeviceToDevice.values)
    }

    private var lastPointerAcceleration: Double?
    private var lastPointerSensitivity: Double?
    private var lastDisablePointerAcceleration: Bool?

    @Published var lastActiveDevice: Device?

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

    private func deviceAdded(_: PointerDeviceManager, pointerDevice: PointerDevice) {
        guard let device = Device(self, pointerDevice) else {
            os_log("Unsupported device: %{public}@",
                   log: Self.log, type: .debug,
                   String(describing: pointerDevice))
            return
        }

        pointerDeviceToDevice[pointerDevice] = device

        os_log("Device added: %{public}@",
               log: Self.log, type: .debug,
               String(describing: device))

        renewPointerSpeed(forDevice: device)
    }

    private func deviceRemoved(_: PointerDeviceManager, pointerDevice: PointerDevice) {
        guard let device = pointerDeviceToDevice[pointerDevice] else { return }

        if lastActiveDevice == device {
            lastActiveDevice = nil
        }

        pointerDeviceToDevice.removeValue(forKey: pointerDevice)

        os_log("Device removed: %{public}@",
               log: Self.log, type: .debug,
               String(describing: device))
    }

    func updatePointerSpeed(acceleration: Double, sensitivity: Double, disableAcceleration: Bool) {
        lastPointerAcceleration = acceleration
        lastPointerSensitivity = sensitivity
        lastDisablePointerAcceleration = disableAcceleration
        for device in devices {
            device.updatePointerSpeed(
                acceleration: acceleration,
                sensitivity: sensitivity,
                disableAcceleration: disableAcceleration
            )
        }
    }

    func renewPointerSpeed() {
        if let acceleration = lastPointerAcceleration,
           let sensitivity = lastPointerSensitivity,
           let disableAcceleration = lastDisablePointerAcceleration {
            updatePointerSpeed(
                acceleration: acceleration,
                sensitivity: sensitivity,
                disableAcceleration: disableAcceleration
            )
        }
    }

    func renewPointerSpeed(forDevice device: Device) {
        if let acceleration = lastPointerAcceleration,
           let sensitivity = lastPointerSensitivity,
           let disableAcceleration = lastDisablePointerAcceleration {
            device.updatePointerSpeed(
                acceleration: acceleration,
                sensitivity: sensitivity,
                disableAcceleration: disableAcceleration
            )
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
}
