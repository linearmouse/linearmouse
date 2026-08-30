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

enum DeviceManagerLogitechTeardownPolicy: Int, Comparable {
    /// Drop monitor ownership without any HID++ reporting I/O.
    case abandon
    /// Preserve a store-backed baseline across sleep without restoring it.
    case sleepPreserve
    /// Restore every pending baseline before invalidating PointerDevice.
    case restore

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The strongest teardown request received for the current observation
/// lifetime. Sleep is a preservation policy, not a terminal outcome: once a
/// caller asks to restore hardware, a later sleep notification must never
/// weaken that request.
struct DeviceManagerStopIntent: Equatable {
    private(set) var logitechTeardownPolicy: DeviceManagerLogitechTeardownPolicy

    mutating func merge(_ other: Self) {
        logitechTeardownPolicy = max(logitechTeardownPolicy, other.logitechTeardownPolicy)
    }
}

/// Tracks the asynchronous Logitech teardown separately from the final stop
/// intent. A completed sleep barrier cannot satisfy a subsequently upgraded
/// terminal restore.
struct DeviceManagerLogitechStopBarrier: Equatable {
    typealias Start = DeviceManagerLogitechTeardownPolicy

    private(set) var highestStarted: DeviceManagerLogitechTeardownPolicy?
    private(set) var highestCompleted: DeviceManagerLogitechTeardownPolicy?

    mutating func startNeeded(for intent: DeviceManagerStopIntent) -> Start? {
        let policy = intent.logitechTeardownPolicy
        guard highestStarted.map({ $0 < policy }) ?? true else {
            return nil
        }
        highestStarted = policy
        return policy
    }

    mutating func complete(_ start: Start) {
        highestCompleted = max(highestCompleted ?? .abandon, start)
    }

    func isSatisfied(for intent: DeviceManagerStopIntent) -> Bool {
        guard let highestCompleted else {
            return false
        }
        return highestCompleted >= intent.logitechTeardownPolicy
    }
}

/// Owns every mutable part of one running -> stopped transition. Asynchronous
/// callbacks may update only the exact request they captured, so a late worker
/// from an earlier observation lifetime cannot satisfy a newer stop.
final class DeviceManagerStopRequest {
    var intent: DeviceManagerStopIntent
    var logitechBarrier = DeviceManagerLogitechStopBarrier()
    var completions = [() -> Void]()
    var sleepLogitechCleanup: BoundedCleanupRequest?
    var sleepTimeoutAuthorization: CancellationSource?
    var terminalLogitechCleanup: BoundedCleanupRequest?

    init(intent: DeviceManagerStopIntent) {
        self.intent = intent
    }
}

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")
    private static let sleepLogitechTeardownTimeout: TimeInterval = 1
    // A monitor request committed just before stop retains the channel lock for
    // at most the HID++ 2s transaction deadline. Leave a small margin for the
    // targeted identity probe, then reserve the remaining global budget for
    // actual setting restoration.
    private static let terminalLogitechTargetValidationTimeout: TimeInterval = 2.25
    private static let terminalLogitechRestoreTimeout: TimeInterval = 4

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
        stop(logitechTeardownPolicy: .abandon)
    }

    private var state: DeviceManagerLifecycleState = .stopped
    private var stopRequest: DeviceManagerStopRequest?

    private var subscriptions = Set<AnyCancellable>()

    private var activateApplicationObserver: Any?

    var allowsDeviceWork: Bool {
        state.allowsDeviceWork
    }

    func stop(
        logitechTeardownPolicy: DeviceManagerLogitechTeardownPolicy = .restore,
        completion: (() -> Void)? = nil
    ) {
        let requestedIntent = DeviceManagerStopIntent(logitechTeardownPolicy: logitechTeardownPolicy)
        switch state {
        case .stopped:
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
            return
        case .stopping, .finishing:
            guard let request = stopRequest else {
                assertionFailure("A stopping DeviceManager must own a stop request")
                if let completion {
                    DispatchQueue.main.async(execute: completion)
                }
                return
            }
            if let completion {
                request.completions.append(completion)
            }
            request.intent.merge(requestedIntent)
            // Keep the devices alive, begin any newly-required stronger
            // Logitech barrier, and let attemptFinish re-evaluate the merged
            // intent before invalidating PointerDevice.
            startLogitechBarrierIfNeeded(for: request)
            return
        case .running:
            state = .stopping
            let request = DeviceManagerStopRequest(intent: requestedIntent)
            if let completion {
                request.completions.append(completion)
            }
            stopRequest = request
        }

        subscriptions.removeAll()

        if let activateApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateApplicationObserver)
            self.activateApplicationObserver = nil
        }

        guard let stopRequest else {
            assertionFailure("A running DeviceManager failed to create its stop request")
            return
        }
        startLogitechBarrierIfNeeded(for: stopRequest)
    }

    private func startLogitechBarrierIfNeeded(for request: DeviceManagerStopRequest) {
        guard stopRequest === request else {
            return
        }
        guard let start = request.logitechBarrier.startNeeded(for: request.intent)
        else {
            attemptFinishStop(request)
            return
        }

        let devices = Array(pointerDeviceToDevice.values)
        if start == .abandon {
            for device in devices {
                device.abandonLogitechControlsMonitoring()
            }
            request.logitechBarrier.complete(.abandon)
            attemptFinishStop(request)
            return
        }

        if start == .restore {
            // A terminal request owns every remaining restore. Completing the
            // weaker sleep bound first prevents its timeout hook from
            // abandoning controls after terminal restoration has begun.
            request.sleepTimeoutAuthorization?.cancel()
            request.sleepTimeoutAuthorization = nil
            request.sleepLogitechCleanup?.complete()
            startTerminalLogitechRestore(devices: devices, request: request, start: start)
            return
        }

        startSleepLogitechTeardown(devices: devices, request: request, start: start)
    }

    private func startSleepLogitechTeardown(
        devices: [Device],
        request: DeviceManagerStopRequest,
        start: DeviceManagerLogitechStopBarrier.Start
    ) {
        let group = DispatchGroup()
        for device in devices {
            group.enter()
            let completion = {
                group.leave()
            }
            switch start {
            case .abandon:
                break
            case .sleepPreserve:
                device.stopLogitechControlsMonitoringForSleep(completion: completion)
            case .restore:
                break
            }

            if device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID {
                group.enter()
                device.prepareLogitechSettingsForSleep {
                    group.leave()
                }
            }
        }

        let logitechDevices = devices.filter {
            $0.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
        }
        let timeoutAuthorization = CancellationSource()
        let cleanup = BoundedCleanupRequest(
            timeout: Self.sleepLogitechTeardownTimeout,
            onTimeout: {
                guard timeoutAuthorization.token.shouldContinue else {
                    return
                }
                os_log(
                    "Timed out preparing Logitech hardware for sleep",
                    log: Self.log,
                    type: .error
                )
                for device in logitechDevices {
                    device.cancelLogitechTeardown()
                }
            },
            completion: { [weak self, weak request] _ in
                guard let self,
                      let request,
                      self.stopRequest === request
                else {
                    return
                }
                request.sleepLogitechCleanup = nil
                if request.sleepTimeoutAuthorization === timeoutAuthorization {
                    request.sleepTimeoutAuthorization = nil
                }
                request.logitechBarrier.complete(start)
                self.attemptFinishStop(request)
            }
        )
        request.sleepLogitechCleanup = cleanup
        request.sleepTimeoutAuthorization = timeoutAuthorization

        group.notify(queue: .global(qos: .utility)) { [weak cleanup] in
            cleanup?.complete()
        }
    }

    /// Restores every Logitech mutation while PointerDevice and receiver
    /// channels are still alive. Each transport remains internally serialized,
    /// while independent devices may make progress in parallel. The bounded
    /// request, rather than worker termination, owns the manager barrier.
    private func startTerminalLogitechRestore(
        devices: [Device],
        request: DeviceManagerStopRequest,
        start: DeviceManagerLogitechStopBarrier.Start
    ) {
        let deadline = Date().addingTimeInterval(Self.terminalLogitechRestoreTimeout)
        let cancellationSource = CancellationSource()
        let logitechDevices = devices.filter {
            $0.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
        }
        for device in logitechDevices {
            device.freezeLogitechForTerminalTeardown()
        }
        let receiverLocationIDs = Set(logitechDevices.compactMap { device -> Int? in
            guard shouldMonitorReceiver(device) else {
                return nil
            }
            return device.pointerDevice.locationID
        })
        let receiverTeardowns = receiverMonitor.beginTerminalTeardown(
            locationIDs: receiverLocationIDs
        )
        let receiverTeardownReferences = receiverTeardowns.map(WeakRef.init)
        let group = DispatchGroup()

        let cleanup = BoundedCleanupRequest(
            timeout: Self.terminalLogitechRestoreTimeout,
            onTimeout: {
                os_log(
                    "Timed out restoring Logitech hardware before teardown",
                    log: Self.log,
                    type: .error
                )
                cancellationSource.cancel()
                for device in logitechDevices {
                    device.cancelLogitechTeardown()
                }
                for teardown in receiverTeardowns {
                    teardown.finish()
                }
            },
            completion: { [weak self, weak request] _ in
                guard let self,
                      let request,
                      self.stopRequest === request
                else {
                    return
                }
                request.terminalLogitechCleanup = nil
                request.logitechBarrier.complete(start)
                attemptFinishStop(request)
            }
        )
        request.terminalLogitechCleanup = cleanup

        // Enter every device before starting asynchronous receiver readiness,
        // so the final group cannot reach zero while a terminal channel is
        // still being opened. Receiver-routed settings start only after that
        // exact teardown has resolved/restored its shared channel.
        for _ in logitechDevices {
            group.enter()
        }

        let receiverDevicesByLocation = Dictionary(grouping: logitechDevices.filter {
            shouldMonitorReceiver($0) && $0.pointerDevice.locationID != nil
        }) { device in
            device.pointerDevice.locationID!
        }
        let preparedReceiverLocations = Set(receiverTeardowns.map(\.locationID))

        for device in logitechDevices where !shouldMonitorReceiver(device) {
            startTerminalLogitechRestore(for: device, deadline: deadline) {
                group.leave()
            }
        }

        for device in logitechDevices
            where shouldMonitorReceiver(device) && device.pointerDevice.locationID == nil {
            os_log(
                "Skip terminal Logitech receiver restore without a locationID: device=%{public}@",
                log: Self.log,
                type: .error,
                String(describing: device)
            )
            device.updateLogitechReceiverDiscovery(nil)
            group.leave()
        }

        for teardown in receiverTeardowns {
            group.enter()
            let devices = receiverDevicesByLocation[teardown.locationID] ?? []
            let restoreIsCurrent = { [weak self, weak request, weak cleanup] in
                guard let self,
                      let request,
                      let cleanup
                else {
                    return false
                }
                return self.stopRequest === request
                    && request.terminalLogitechCleanup === cleanup
                    && cancellationSource.token.shouldContinue
            }
            let validationGroup = DispatchGroup()

            for device in devices {
                guard let expectedRoute = device.logitechReceiverRouteSnapshot,
                      expectedRoute.identity.serialNumber != nil
                      || teardown.retainedAdmissionChannel
                else {
                    device.updateLogitechReceiverDiscovery(nil)
                    group.leave()
                    continue
                }

                validationGroup.enter()
                let validationDeadline = min(
                    deadline,
                    Date().addingTimeInterval(Self.terminalLogitechTargetValidationTimeout)
                )
                teardown.validateLogicalDevice(
                    for: device.pointerDevice,
                    slot: expectedRoute.slot,
                    deadline: validationDeadline,
                    until: restoreIsCurrent
                ) { [weak self] freshIdentity in
                    defer { validationGroup.leave() }
                    guard let self,
                          restoreIsCurrent(),
                          let freshIdentity,
                          Self.terminalIdentityMatches(
                              expected: expectedRoute.identity,
                              fresh: freshIdentity,
                              retainedAdmissionChannel: teardown.retainedAdmissionChannel
                          )
                    else {
                        device.updateLogitechReceiverDiscovery(nil)
                        group.leave()
                        return
                    }

                    let route = LogitechReceiverRoute(
                        slot: freshIdentity.slot,
                        identity: freshIdentity
                    )
                    device.updateLogitechReceiverDiscovery(.init(
                        identities: [freshIdentity],
                        route: route
                    ))
                    self.startTerminalLogitechRestore(for: device, deadline: deadline) {
                        group.leave()
                    }
                }
            }

            validationGroup.notify(queue: .main) {
                guard restoreIsCurrent() else {
                    group.leave()
                    return
                }
                teardown.restoreOwnedNotificationFlags(until: restoreIsCurrent) {
                    group.leave()
                }
            }
        }

        for (locationID, devices) in receiverDevicesByLocation
            where !preparedReceiverLocations.contains(locationID) {
            os_log(
                "Skip terminal Logitech device restore because no exact receiver channel is available: locationID=%{public}d",
                log: Self.log,
                type: .error,
                locationID
            )
            devices.forEach { _ in group.leave() }
        }

        group.notify(queue: .global(qos: .utility)) { [weak cleanup] in
            guard let cleanup else {
                return
            }

            let finishGroup = DispatchGroup()
            for reference in receiverTeardownReferences {
                guard let teardown = reference.value else {
                    continue
                }
                finishGroup.enter()
                teardown.finish {
                    finishGroup.leave()
                }
            }
            finishGroup.notify(queue: .global(qos: .utility)) { [weak cleanup] in
                cleanup?.complete()
            }
        }
    }

    private func startTerminalLogitechRestore(
        for device: Device,
        deadline: Date,
        completion: @escaping () -> Void
    ) {
        let group = DispatchGroup()
        group.enter()
        device.restorePendingLogitechControlsForTeardown {
            group.leave()
        }

        group.enter()
        device.restoreLogitechSettingsForTeardown(deadline: deadline) { restored in
            if !restored, Date() < deadline {
                os_log(
                    "Failed to restore all Logitech settings before teardown: device=%{public}@",
                    log: Self.log,
                    type: .error,
                    String(describing: device)
                )
            }
            group.leave()
        }
        group.notify(queue: .main, execute: completion)
    }

    static func terminalIdentityMatches(
        expected: ReceiverLogicalDeviceIdentity,
        fresh: ReceiverLogicalDeviceIdentity,
        retainedAdmissionChannel: Bool
    ) -> Bool {
        let normalizeSerial: (String?) -> String? = {
            guard let value = $0 else {
                return nil
            }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return normalized.isEmpty ? nil : normalized
        }
        if let expectedSerial = normalizeSerial(expected.serialNumber) {
            return normalizeSerial(fresh.serialNumber) == expectedSerial
        }

        guard retainedAdmissionChannel,
              expected.receiverLocationID == fresh.receiverLocationID,
              expected.slot == fresh.slot,
              expected.kind == fresh.kind
        else {
            return false
        }
        if let expectedProductID = expected.productID {
            return fresh.productID == expectedProductID
        }
        return expected.name == fresh.name
    }

    private func attemptFinishStop(_ request: DeviceManagerStopRequest) {
        guard state == .stopping,
              stopRequest === request
        else {
            return
        }
        let intent = request.intent
        guard request.logitechBarrier.isSatisfied(for: intent) else {
            return
        }
        state = .finishing

        finishDeviceLifecycleTeardown()

        // Software restoration can reenter stop(). If that upgraded the intent
        // or introduced a stronger Logitech barrier, keep PointerDevice alive
        // and schedule another non-recursive finish pass.
        guard stopRequest === request else {
            return
        }
        let finalIntent = request.intent
        guard finalIntent == intent,
              request.logitechBarrier.isSatisfied(for: finalIntent)
        else {
            state = .stopping
            DispatchQueue.main.async { [weak self, weak request] in
                guard let request else {
                    return
                }
                self?.attemptFinishStop(request)
            }
            return
        }

        manager.stopObservation()
        state = .stopped
        stopRequest = nil

        let completions = request.completions
        request.completions.removeAll()
        request.sleepTimeoutAuthorization?.cancel()
        request.sleepTimeoutAuthorization = nil
        request.sleepLogitechCleanup = nil
        request.terminalLogitechCleanup = nil
        completions.forEach { $0() }
    }

    func start() {
        guard state == .stopped else {
            return
        }
        state = .running

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

    private func finishDeviceLifecycleTeardown() {
        for device in devices {
            device.finishLifecycleTeardown()
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
