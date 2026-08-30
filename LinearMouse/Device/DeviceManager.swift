// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Foundation
import os.log
import PointerKit

enum DeviceManagerLifecycleState: Equatable {
    case stopped
    case running
    case stopping
    case finishing

    var allowsDeviceWork: Bool {
        self == .running
    }
}

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")

    private let manager = PointerDeviceManager()
    private let receiverMonitor = ReceiverMonitor()
    let logitechHardwareBaselineStore = LogitechHardwareBaselineStore()

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
            manager
                .observePropertyChanged(property: property) { [self] _ in
                    os_log("Property %{public}@ changed", log: Self.log, type: .info, property)
                    updatePointerSpeed()
                }
                .tieToLifetime(of: self)
        }
    }

    deinit {
        stop(
            restoringHighResolutionWheel: false,
            restoringLogitechControls: false
        )
    }

    private var state: DeviceManagerLifecycleState = .stopped
    private var stopCompletions = [() -> Void]()
    private var skipHighResolutionWheelRestore = false
    private var applyingSleepHiResPolicy = false

    private var subscriptions = Set<AnyCancellable>()

    private var activateApplicationObserver: Any?

    var allowsDeviceWork: Bool {
        state.allowsDeviceWork
    }

    func stop(
        restoringHighResolutionWheel: Bool = true,
        restoringLogitechControls: Bool = true,
        applyingSleepHiResPolicy: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        switch state {
        case .stopped:
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
            return
        case .stopping:
            if let completion {
                stopCompletions.append(completion)
            }
            skipHighResolutionWheelRestore = skipHighResolutionWheelRestore || !restoringHighResolutionWheel
            self.applyingSleepHiResPolicy = self.applyingSleepHiResPolicy || applyingSleepHiResPolicy
            if !restoringLogitechControls {
                for value in pointerDeviceToDevice.values {
                    value.stopLogitechControlsMonitoringForSleep()
                }
                finishStop(restoringHighResolutionWheel: false)
            }
            return
        case .finishing:
            // Main-run-loop HID restoration can deliver lifecycle events
            // reentrantly. The current teardown already owns the devices;
            // queue only the caller's continuation and never enter finishStop
            // recursively.
            if let completion {
                stopCompletions.append(completion)
            }
            self.applyingSleepHiResPolicy = self.applyingSleepHiResPolicy || applyingSleepHiResPolicy
            if !restoringHighResolutionWheel {
                skipHighResolutionWheelRestore = true
                // Cancel the request currently pumping the run loop. The
                // owning finishStop remains responsible for the teardown;
                // subsequent devices observe the downgraded no-I/O intent.
                for value in pointerDeviceToDevice.values {
                    value.prepareHighResolutionWheelForReconnect()
                }
            }
            return
        case .running:
            state = .stopping
            skipHighResolutionWheelRestore = !restoringHighResolutionWheel
            self.applyingSleepHiResPolicy = applyingSleepHiResPolicy
        }

        if let completion {
            stopCompletions.append(completion)
        }

        subscriptions.removeAll()

        if let activateApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateApplicationObserver)
            self.activateApplicationObserver = nil
        }

        let devices = Array(pointerDeviceToDevice.values)
        guard restoringLogitechControls else {
            devices.forEach { $0.stopLogitechControlsMonitoringForSleep() }
            finishStop(restoringHighResolutionWheel: restoringHighResolutionWheel)
            return
        }

        let group = DispatchGroup()
        for device in devices {
            group.enter()
            device.disableLogitechControlsMonitoring {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finishStop(restoringHighResolutionWheel: restoringHighResolutionWheel)
        }
    }

    private func finishStop(restoringHighResolutionWheel: Bool) {
        guard state == .stopping else {
            return
        }
        state = .finishing

        restorePointerSpeedToInitialValue(
            restoringHighResolutionWheel: restoringHighResolutionWheel,
            applyingSleepHiResPolicy: applyingSleepHiResPolicy
        )
        manager.stopObservation()
        state = .stopped
        skipHighResolutionWheelRestore = false
        applyingSleepHiResPolicy = false

        let completions = stopCompletions
        stopCompletions.removeAll()
        completions.forEach { $0() }
    }

    func start() {
        guard state == .stopped else {
            return
        }
        state = .running
        skipHighResolutionWheelRestore = false

        // Input callbacks suppress events from the device that was previously
        // active. A new observation lifetime needs its first physical input to
        // pass through so it can reconcile hardware state after a wake.
        lastActiveDeviceId = nil
        lastActiveDeviceRef = nil

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
                    self.updateLogitechDeviceSettings()
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
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            os_log(
                "Frontmost app changed: %{public}@",
                log: Self.log,
                type: .info,
                application?.bundleIdentifier ?? "(nil)"
            )
            self?.updatePointerSpeed()
        }

        updatePointerSpeed()
        updateLogitechDeviceSettings()
    }

    private func deviceAdded(_: PointerDeviceManager, _ pointerDevice: PointerDevice) {
        guard allowsDeviceWork else {
            os_log(
                "Drop device added while lifecycle does not admit device work: %{public}@",
                log: Self.log,
                type: .info,
                String(describing: pointerDevice)
            )
            return
        }

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

        if shouldMonitorReceiver(device) {
            receiverMonitor.startMonitoring(device: device)
        }

        updatePointerSpeed(for: device)
        updateLogitechDeviceSettings(for: device)
        if device.hasLogitechControlsMonitor, !shouldMonitorReceiver(device) {
            device.requestLogitechControlsForcedReconfiguration()
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
        guard state == .running else {
            return
        }

        for device in devices {
            updatePointerSpeed(for: device)
        }
    }

    func updatePointerSpeed(for device: Device) {
        guard state == .running else {
            return
        }

        let scheme = ConfigurationState.shared.configuration.matchScheme(
            withDevice: device,
            withPid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
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

    func updateLogitechDeviceSettings() {
        guard state == .running else {
            return
        }

        for device in devices {
            updateLogitechDeviceSettings(for: device)
        }
    }

    func updateLogitechDeviceSettings(for device: Device) {
        guard state == .running,
              device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
        else {
            return
        }

        guard updateLogitechReceiverDiscovery(for: device) else {
            return
        }

        device.logitechSettingsReconciler.apply(configuredLogitechDeviceSettings(for: device))
    }

    private func configuredLogitechDeviceSettings(for device: Device) -> LogitechDeviceSettings {
        let schemes = ConfigurationState.shared.configuration.schemes
        guard case let .at(index) = schemes.schemeIndex(
            ofDevice: device,
            ofApp: nil,
            ofProcessPath: nil,
            ofDisplay: nil
        ) else {
            return LogitechDeviceSettings(dpi: nil, highResolutionWheel: nil)
        }

        let scheme = schemes[index]
        return LogitechDeviceSettings(
            dpi: scheme.pointer.hardwareDPI,
            highResolutionWheel: scheme.logitech.highResolutionWheel
        )
    }

    func restorePointerSpeedToInitialValue(
        restoringHighResolutionWheel: Bool = true,
        applyingSleepHiResPolicy: Bool = false
    ) {
        for device in devices {
            let restoresHighResolutionWheel = restoringHighResolutionWheel
                && !skipHighResolutionWheelRestore
            device.restorePointerAccelerationAndPointerSpeed(
                restoringHighResolutionWheel: restoresHighResolutionWheel,
                waitForHighResolutionWheelRestore: restoresHighResolutionWheel,
                applyingSleepHiResPolicy: applyingSleepHiResPolicy
            )
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
        guard state == .running, lastActiveDeviceId != device.id else {
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
        // A device's first input after observation starts is the reliable
        // signal that it is ready. Force a full reconciliation even when it
        // was not previously active.
        reapplyLogitechDeviceSettings(for: device)
    }

    func requestLogitechReceiverRediscovery() {
        guard state == .running else {
            return
        }

        for device in devices where shouldMonitorReceiver(device) {
            // The wake poke is for receiver route recovery only. Direct
            // devices may already have a confirmation attempt scheduled;
            // restarting it here would cancel that work.
            let identities = device.pointerDevice.locationID.flatMap {
                receiverPairedDeviceIdentities[$0]
            }
            if identities?.isEmpty != false {
                receiverMonitor.requestRediscovery(device: device)
            }
        }
    }

    private func reapplyLogitechDeviceSettings(for device: Device) {
        guard state == .running,
              device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID else {
            return
        }

        guard updateLogitechReceiverDiscovery(for: device) else {
            if shouldMonitorReceiver(device) {
                receiverMonitor.requestRediscovery(device: device)
            }
            return
        }

        device.logitechSettingsReconciler.reapply(configuredLogitechDeviceSettings(for: device))
    }

    /// Returns false for a monitored receiver until discovery has identified a
    /// unique pointing-device slot. Direct devices are ready immediately.
    @discardableResult
    private func updateLogitechReceiverDiscovery(for device: Device) -> Bool {
        guard shouldMonitorReceiver(device) else {
            device.updateLogitechReceiverDiscovery(nil)
            return true
        }

        guard let locationID = device.pointerDevice.locationID,
              let identities = receiverPairedDeviceIdentities[locationID]
        else {
            device.updateLogitechReceiverDiscovery(nil)
            return false
        }

        let route = LogitechReceiverRouteResolver.resolve(
            for: device.pointerDevice,
            identities: identities
        )
        device.updateLogitechReceiverDiscovery(.init(identities: identities, route: route))
        return route != nil
    }

    func pairedReceiverDevices(for device: Device) -> [ReceiverLogicalDeviceIdentity] {
        guard shouldMonitorReceiver(device),
              let locationID = device.pointerDevice.locationID
        else {
            return []
        }

        return receiverPairedDeviceIdentities[locationID] ?? []
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
        LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.pointerDevice.transport
        )
    }

    private func receiverPointingDevicesChanged(locationID: Int, identities: [ReceiverLogicalDeviceIdentity]) {
        guard state == .running,
              pointerDeviceToDevice.values.contains(where: { $0.pointerDevice.locationID == locationID }) else {
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

        let previousSlots = Set(previousIdentities.map(\.slot))
        for (_, device) in pointerDeviceToDevice where device.pointerDevice.locationID == locationID {
            let previousRoute = device.logitechReceiverRouteSnapshot
            let isReady = updateLogitechReceiverDiscovery(for: device)
            guard isReady, let route = device.logitechReceiverRouteSnapshot else {
                if !identities.isEmpty {
                    device.requestLogitechControlsForcedReconfiguration()
                }
                continue
            }

            let routeChanged = LogitechReceiverRoute.hardwareTargetChanged(from: previousRoute, to: route)
            let identityChanged = previousRoute != route
            let slotReconnected = !previousSlots.contains(route.slot)
            if routeChanged || slotReconnected {
                reapplyLogitechDeviceSettings(for: device)
            } else if identityChanged {
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
