// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit
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

    @Published var lastActiveDeviceRef: WeakRef<Device>?

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

        for property in [
            kIOHIDMouseAccelerationType,
            kIOHIDTrackpadAccelerationType,
            kIOHIDPointerResolutionKey,
            "HIDUseLinearScalingMouseAcceleration"
        ] {
            manager.observePropertyChanged(property: property) { [self] _ in
                os_log("Property %{public}@ changed", log: Self.log, type: .info, property)
                updatePointerSpeed()
            }.tieToLifetime(of: self)
        }
    }

    deinit {
        stop()
    }

    private enum State {
        case stopped, running
    }

    private var state: State = .stopped

    private var subscriptions = Set<AnyCancellable>()

    private var activateApplicationObserver: Any?

    func stop() {
        guard state == .running else {
            return
        }
        state = .stopped

        restorePointerSpeedToInitialValue()
        manager.stopObservation()
        subscriptions.removeAll()

        if let activateApplicationObserver = activateApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateApplicationObserver)
        }
    }

    func start() {
        guard state == .stopped else {
            return
        }
        state = .running

        manager.startObservation()

        ConfigurationState.shared.$configuration
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else {
                    return
                }
                DispatchQueue.main.async {
                    self.updatePointerSpeed()
                }
            }
            .store(in: &subscriptions)

        ScreenManager.shared.$currentScreenName
            .sink { [weak self] _ in
                guard let self = self else {
                    return
                }
                DispatchQueue.main.async {
                    self.updatePointerSpeed()
                }
            }
            .store(in: &subscriptions)

        activateApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                os_log("Frontmost app changed: %{public}@", log: Self.log, type: .info,
                       NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "(nil)")
                self?.updatePointerSpeed()
            }
        )
    }

    private func deviceAdded(_: PointerDeviceManager, _ pointerDevice: PointerDevice) {
        let device = Device(self, pointerDevice)

        objectWillChange.send()

        pointerDeviceToDevice[pointerDevice] = device
        devices.append(device)

        os_log("Device added: %{public}@",
               log: Self.log, type: .info,
               String(describing: device))

        updatePointerSpeed(for: device)
    }

    private func deviceRemoved(_: PointerDeviceManager, _ pointerDevice: PointerDevice) {
        guard let device = pointerDeviceToDevice[pointerDevice] else { return }
        device.markRemoved()

        objectWillChange.send()

        if lastActiveDeviceRef?.value == device {
            lastActiveDeviceRef = nil
        }

        pointerDeviceToDevice.removeValue(forKey: pointerDevice)
        devices.removeAll { $0 == device }

        os_log("Device removed: %{public}@",
               log: Self.log, type: .info,
               String(describing: device))
    }

    /// Observes events from `DeviceManager`.
    ///
    /// It seems that extenal Trackpads do not trigger to `IOHIDDevice`'s inputValueCallback.
    /// That's why we need to observe events from `DeviceManager` too.
    private func eventReceived(_: PointerDeviceManager, _ pointerDevice: PointerDevice, _ event: IOHIDEvent) {
        guard let device = pointerDeviceToDevice[pointerDevice] else {
            return
        }

        guard IOHIDEventGetType(event) == kIOHIDEventTypeScroll else {
            return
        }

        let scrollX = IOHIDEventGetFloatValue(event, kIOHIDEventFieldScrollX)
        let scrollY = IOHIDEventGetFloatValue(event, kIOHIDEventFieldScrollY)
        guard scrollX != 0 || scrollY != 0 else {
            return
        }

        if lastActiveDeviceRef?.value != device {
            lastActiveDeviceRef = .init(device)
            os_log("""
                   Last active device changed: %{public}@, category=%{public}@ \
                   (Reason: Received event from DeviceManager)
                   """,
                   log: Self.log, type: .info,
                   String(describing: device),
                   String(describing: device.category))
        }
    }

    func deviceFromCGEvent(_ cgEvent: CGEvent) -> Device? {
        // Issue: https://github.com/linearmouse/linearmouse/issues/677#issuecomment-1938208542
        guard ![.flagsChanged, .keyDown, .keyUp].contains(cgEvent.type) else {
            return lastActiveDeviceRef?.value
        }

        guard let ioHIDEvent = CGEventCopyIOHIDEvent(cgEvent) else {
            return lastActiveDeviceRef?.value
        }

        guard let pointerDevice = manager.pointerDeviceFromIOHIDEvent(ioHIDEvent) else {
            return lastActiveDeviceRef?.value
        }

        return pointerDeviceToDevice[pointerDevice]
    }

    func updatePointerSpeed() {
        for device in devices {
            updatePointerSpeed(for: device)
        }
    }

    func updatePointerSpeed(for device: Device) {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let scheme = ConfigurationState.shared.configuration.matchScheme(withDevice: device,
                                                                         withPid: frontmostApp?.processIdentifier,
                                                                         withDisplay: ScreenManager.shared
                                                                             .currentScreenName)

        if let pointerDisableAcceleration = scheme.pointer.disableAcceleration, pointerDisableAcceleration {
            // If the pointer acceleration is turned off, it is preferable to utilize
            // the new API introduced by macOS Sonoma.
            // Otherwise, set pointer acceleration to -1.
            if device.disablePointerAcceleration != nil {
                device.disablePointerAcceleration = true

                // This might be a bit confusing because of the historical naming
                // convention, but here, the pointerAcceleration actually refers to
                // the tracking speed.
                if let pointerAcceleration = scheme.pointer.acceleration {
                    device.pointerAcceleration = pointerAcceleration.asTruncatedDouble
                } else {
                    device.restorePointerAcceleration()
                }
            } else {
                device.pointerAcceleration = -1
            }

            return
        }

        if device.disablePointerAcceleration != nil {
            device.disablePointerAcceleration = false
        }

        if let pointerSpeed = scheme.pointer.speed {
            device.pointerSpeed = pointerSpeed.asTruncatedDouble
        } else {
            device.restorePointerSpeed()
        }

        if let pointerAcceleration = scheme.pointer.acceleration {
            device.pointerAcceleration = pointerAcceleration.asTruncatedDouble
        } else {
            device.restorePointerAcceleration()
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
