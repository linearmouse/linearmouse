// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import Foundation
import os.log
import PointerKit

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")

    private let manager = PointerDeviceManager()

    private var pointerDeviceToDevice = [PointerDevice: Device]()
    @Published var devices: [Device] = []

    @Published var lastActiveDevice: Device?

    init() {
        manager.observeDeviceAdded(using: { [weak self] in
            self?.deviceAdded($0, $1)
        }).tieToLifetime(of: self)

        manager.observeDeviceRemoved(using: { [weak self] in
            self?.deviceRemoved($0, $1)
        }).tieToLifetime(of: self)

        manager.observeEventReceived(using: { [weak self] in
            self?.eventReceived($0, $1, $2)
        }).tieToLifetime(of: self)

        for property in [kIOHIDMouseAccelerationType, kIOHIDTrackpadAccelerationType, kIOHIDPointerResolutionKey] {
            manager.observePropertyChanged(property: property) { [self] _ in
                os_log("Property %@ changed", log: Self.log, type: .debug, property)
                updatePointerSpeed()
            }.tieToLifetime(of: self)
        }
    }

    private var subscriptions = Set<AnyCancellable>()

    func pause() {
        restorePointerSpeedToInitialValue()
        manager.stopObservation()
        subscriptions.removeAll()
    }

    func resume() {
        manager.startObservation()

        ConfigurationState.shared.$configuration.sink { _ in
            DispatchQueue.main.async { [weak self] in
                self?.updatePointerSpeed()
            }
        }
        .store(in: &subscriptions)
    }

    private func deviceAdded(_: PointerDeviceManager, _ pointerDevice: PointerDevice) {
        let device = Device(self, pointerDevice)

        objectWillChange.send()

        pointerDeviceToDevice[pointerDevice] = device
        devices.append(device)

        os_log("Device added: %{public}@",
               log: Self.log, type: .debug,
               String(describing: device))

        updatePointerSpeed(for: device)
    }

    private func deviceRemoved(_: PointerDeviceManager, _ pointerDevice: PointerDevice) {
        guard let device = pointerDeviceToDevice[pointerDevice] else { return }

        objectWillChange.send()

        if lastActiveDevice == device {
            lastActiveDevice = nil
        }

        pointerDeviceToDevice.removeValue(forKey: pointerDevice)
        devices.removeAll { $0 == device }

        os_log("Device removed: %{public}@",
               log: Self.log, type: .debug,
               String(describing: device))
    }

    /// Observes events from `DeviceManager`.
    ///
    /// It seems that extenal Trackpads do not trigger to `IOHIDDevice`'s inputValueCallback.
    /// That's why we need to observe events from `DeviceManager` too.
    private func eventReceived(_: PointerDeviceManager, _ pointerDevice: PointerDevice, _: IOHIDEvent) {
        guard let device = pointerDeviceToDevice[pointerDevice] else { return }

        if lastActiveDevice != device {
            lastActiveDevice = device
            os_log("""
                   Last active device changed: %{public}@, category=%{public}@ \
                   (Reason: Received event from DeviceManager)
                   """,
                   log: Self.log, type: .debug,
                   String(describing: device),
                   String(describing: device.category))
        }
    }

    func updatePointerSpeed() {
        for device in devices {
            updatePointerSpeed(for: device)
        }
    }

    func updatePointerSpeed(for device: Device) {
        let scheme = ConfigurationState.shared.configuration.matchedScheme(withDevice: device)

        if let pointerDisableAcceleration = scheme.pointer?.disableAcceleration {
            if pointerDisableAcceleration {
                device.pointerAcceleration = -1
                return
            }
        }

        if let pointerAcceleration = scheme.pointer?.acceleration {
            device.pointerAcceleration = pointerAcceleration.asTruncatedDouble
        } else {
            device.restorePointerAcceleration()
        }

        if let pointerSpeed = scheme.pointer?.speed {
            device.pointerSpeed = pointerSpeed.asTruncatedDouble
        } else {
            device.restorePointerSpeed()
        }
    }

    func restorePointerSpeedToInitialValue() {
        for device in devices {
            device.restorePointerAccelerationAndPointerSpeed()
        }
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
