// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Foundation
import os.log
import PointerKit

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")

    private let manager = PointerDeviceManager()
    private let receiverMonitor = ReceiverMonitor()

    private var pointerDeviceToDevice = [PointerDevice: Device]()
    @Published private(set) var receiverPairedDeviceIdentities = [Int: [ReceiverLogicalDeviceIdentity]]()
    @Published var devices: [Device] = []

    var lastActiveDeviceId: Int32?
    @Published var lastActiveDeviceRef: WeakRef<Device>?

    init() {
        manager.observeDeviceAdded { [weak self] in
            self?.deviceAdded($0, $1)
        }
        .tieToLifetime(of: self)

        manager.observeDeviceRemoved { [weak self] in
            self?.deviceRemoved($0, $1)
        }
        .tieToLifetime(of: self)

        manager.observeEventReceived { [weak self] in
            self?.eventReceived($0, $1, $2)
        }
        .tieToLifetime(of: self)

        receiverMonitor.onPointingDevicesChanged = { [weak self] locationID, identities in
            self?.receiverPointingDevicesChanged(locationID: locationID, identities: identities)
        }

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

        if let activateApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateApplicationObserver)
        }
    }

    func start() {
        guard state == .stopped else {
            return
        }
        state = .running

        manager.startObservation()

        ConfigurationState.shared
            .$configuration
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                DispatchQueue.main.async {
                    self.updatePointerSpeed()
                }
            }
            .store(in: &subscriptions)

        ScreenManager.shared
            .$currentScreenName
            .sink { [weak self] _ in
                guard let self else {
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
            queue: .main
        ) { [weak self] _ in
            os_log(
                "Frontmost app changed: %{public}@",
                log: Self.log,
                type: .info,
                FrontmostApplicationTracker.shared.bundleIdentifier ?? "(nil)"
            )
            self?.updatePointerSpeed()
        }
    }

    private func deviceAdded(_: PointerDeviceManager, _ pointerDevice: PointerDevice) {
        let device = Device(self, pointerDevice)

        objectWillChange.send()

        pointerDeviceToDevice[pointerDevice] = device
        refreshVisibleDevices()

        os_log(
            "Device added: %{public}@",
            log: Self.log,
            type: .info,
            String(describing: device)
        )

        updatePointerSpeed(for: device)

        if shouldMonitorReceiver(device) {
            receiverMonitor.startMonitoring(device: device)
        }
    }

    private func deviceRemoved(_: PointerDeviceManager, _ pointerDevice: PointerDevice) {
        guard let device = pointerDeviceToDevice[pointerDevice] else {
            return
        }
        device.markRemoved()

        objectWillChange.send()

        if lastActiveDeviceId == device.id {
            lastActiveDeviceId = nil
            lastActiveDeviceRef = nil
        }

        if let locationID = pointerDevice.locationID {
            let hasRemainingReceiverAtLocation = pointerDeviceToDevice
                .filter { $0.key != pointerDevice }
                .contains { _, existingDevice in
                    existingDevice.pointerDevice.locationID == locationID && shouldMonitorReceiver(existingDevice)
                }

            if hasRemainingReceiverAtLocation {
                os_log(
                    "Keep receiver monitor running because another receiver device shares locationID=%{public}d",
                    log: Self.log,
                    type: .info,
                    locationID
                )
            } else {
                receiverMonitor.stopMonitoring(device: device)
                receiverPairedDeviceIdentities.removeValue(forKey: locationID)
            }
        }

        pointerDeviceToDevice.removeValue(forKey: pointerDevice)
        refreshVisibleDevices()

        os_log(
            "Device removed: %{public}@",
            log: Self.log,
            type: .info,
            String(describing: device)
        )
    }

    /// Observes events from `DeviceManager`.
    ///
    /// It seems that extenal Trackpads do not trigger to `IOHIDDevice`'s inputValueCallback.
    /// That's why we need to observe events from `DeviceManager` too.
    private func eventReceived(_: PointerDeviceManager, _ pointerDevice: PointerDevice, _ event: IOHIDEvent) {
        guard let physicalDevice = pointerDeviceToDevice[pointerDevice] else {
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

        markDeviceActive(physicalDevice, reason: "Received event from DeviceManager")
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

        guard let physicalDevice = pointerDeviceToDevice[pointerDevice] else {
            return lastActiveDeviceRef?.value
        }

        return physicalDevice
    }

    func updatePointerSpeed() {
        for device in devices {
            updatePointerSpeed(for: device)
        }
    }

    func updatePointerSpeed(for device: Device) {
        let scheme = ConfigurationState.shared.configuration.matchScheme(
            withDevice: device,
            withPid: FrontmostApplicationTracker.shared.processIdentifier,
            withDisplay: ScreenManager.shared
                .currentScreenName
        )

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
                    switch pointerAcceleration {
                    case let .value(v):
                        device.pointerAcceleration = v.asTruncatedDouble
                    case .unset:
                        device.restorePointerAcceleration()
                    }
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
            switch pointerSpeed {
            case let .value(v):
                device.pointerSpeed = v.asTruncatedDouble
            case .unset:
                device.restorePointerSpeed()
            }
        } else {
            device.restorePointerSpeed()
        }

        if let pointerAcceleration = scheme.pointer.acceleration {
            switch pointerAcceleration {
            case let .value(v):
                device.pointerAcceleration = v.asTruncatedDouble
            case .unset:
                device.restorePointerAcceleration()
            }
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

    func markDeviceActive(_ device: Device, reason: String) {
        guard lastActiveDeviceId != device.id else {
            return
        }

        lastActiveDeviceId = device.id
        lastActiveDeviceRef = .init(device)

        os_log(
            "Last active device changed: %{public}@, category=%{public}@ (Reason: %{public}@)",
            log: Self.log,
            type: .info,
            String(describing: device),
            String(describing: device.category),
            reason
        )

        updatePointerSpeed()
    }

    func pairedReceiverDevices(for device: Device) -> [ReceiverLogicalDeviceIdentity] {
        guard shouldMonitorReceiver(device),
              let locationID = device.pointerDevice.locationID
        else {
            return []
        }

        let identities = receiverPairedDeviceIdentities[locationID] ?? []
        os_log(
            "Receiver paired device lookup: locationID=%{public}d device=%{public}@ count=%{public}u",
            log: Self.log,
            type: .info,
            locationID,
            String(describing: device),
            UInt32(identities.count)
        )
        return identities
    }

    func preferredName(for device: Device, fallback: String? = nil) -> String {
        fallback ?? device.name
    }

    func displayName(for device: Device, fallbackBaseName: String? = nil) -> String {
        Self.displayName(
            baseName: preferredName(for: device, fallback: fallbackBaseName),
            pairedDevices: pairedReceiverDevices(for: device)
        )
    }

    private func shouldMonitorReceiver(_ device: Device) -> Bool {
        guard let vendorID = device.vendorID,
              vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
              device.pointerDevice.transport == PointerDeviceTransportName.usb
        else {
            return false
        }

        let productName = device.productName ?? device.name
        return productName.localizedCaseInsensitiveContains("receiver")
    }

    private func receiverPointingDevicesChanged(locationID: Int, identities: [ReceiverLogicalDeviceIdentity]) {
        guard pointerDeviceToDevice.values.contains(where: { $0.pointerDevice.locationID == locationID }) else {
            os_log(
                "Drop receiver logical device update because no visible device matches locationID=%{public}d count=%{public}u",
                log: Self.log,
                type: .info,
                locationID,
                UInt32(identities.count)
            )
            return
        }

        let previousIdentities = receiverPairedDeviceIdentities[locationID] ?? []
        receiverPairedDeviceIdentities[locationID] = identities

        let identitiesDescription = identities.map { identity in
            let battery = identity.batteryLevel.map(String.init) ?? "(nil)"
            return "slot=\(identity.slot) name=\(identity.name) battery=\(battery)"
        }
        .joined(separator: ", ")

        os_log(
            "Receiver logical devices updated for locationID=%{public}d: %{public}@",
            log: Self.log,
            type: .info,
            locationID,
            identitiesDescription
        )

        // Only trigger forced reconfiguration when a device has actually reconnected
        // (a slot appeared that wasn't in the previous identity set), since device
        // firmware resets diversion state on reconnect.
        let previousSlots = Set(previousIdentities.map(\.slot))
        let hasReconnectedDevice = identities.contains { !previousSlots.contains($0.slot) }
        if hasReconnectedDevice {
            for (_, device) in pointerDeviceToDevice where device.pointerDevice.locationID == locationID {
                device.requestLogitechControlsForcedReconfiguration()
            }
        }
    }

    private func refreshVisibleDevices() {
        devices = pointerDeviceToDevice.values.sorted { $0.id < $1.id }
    }

    static func displayName(baseName: String, pairedDevices: [ReceiverLogicalDeviceIdentity]) -> String {
        guard !pairedDevices.isEmpty else {
            return baseName
        }

        if pairedDevices.count == 1, let pairedName = pairedDevices.first?.name {
            return "\(baseName) (\(pairedName))"
        }

        return String(
            format: NSLocalizedString("%@ (%lld devices)", comment: ""),
            baseName,
            Int64(pairedDevices.count)
        )
    }
}
