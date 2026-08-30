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
    case suspending
    case suspended
    case stopping
    case finishing

    var allowsDeviceWork: Bool {
        self == .running
    }

    var allowsDeviceTopology: Bool {
        self == .running || self == .suspending || self == .suspended
    }
}

enum DeviceManagerLogitechTeardownPolicy: Int, Comparable {
    /// Drop monitor ownership without any HID++ reporting I/O.
    case abandon
    /// Restore every pending baseline before invalidating PointerDevice.
    case restore

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The strongest terminal teardown request received for the current
/// observation lifetime.
struct DeviceManagerStopIntent: Equatable {
    private(set) var logitechTeardownPolicy: DeviceManagerLogitechTeardownPolicy

    mutating func merge(_ other: Self) {
        logitechTeardownPolicy = max(logitechTeardownPolicy, other.logitechTeardownPolicy)
    }
}

/// Tracks the asynchronous Logitech teardown separately from the final stop
/// intent.
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
    var terminalLogitechCleanup: BoundedCleanupRequest?

    init(intent: DeviceManagerStopIntent) {
        self.intent = intent
    }
}

/// Owns one running -> suspended transition. Object identity prevents a late
/// controls-cleanup callback or wake from resolving another sleep cycle.
final class DeviceManagerSuspensionRequest {
    enum Disposition: Equatable {
        case active
        case resumed
        case superseded
    }

    private(set) var disposition = Disposition.active
    var controlsCleanup: BoundedCleanupRequest?
    var logitechSettings = [
        ObjectIdentifier: (device: WeakRef<Device>, suspension: LogitechHardwareSuspension)
    ]()

    @discardableResult
    func claimResume() -> Bool {
        guard disposition == .active else {
            return false
        }
        disposition = .resumed
        return true
    }

    func supersede() {
        disposition = .superseded
    }
}

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DeviceManager")
    private static let sleepControlsTeardownTimeout: TimeInterval = 1
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

        receiverMonitor.onPointingDevicesChanged = { [weak self] locationID, publication in
            self?.receiverPointingDevicesChanged(locationID: locationID, publication: publication)
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
    private var suspensionRequest: DeviceManagerSuspensionRequest?
    private var retainedSuspensionRequests = [ObjectIdentifier: DeviceManagerSuspensionRequest]()
    private var receiverWakeRediscoveryRequests = [Int: ReceiverRediscoveryRequest]()
    private var receiverWakeHardwareSuspensions = [
        ObjectIdentifier: (device: WeakRef<Device>, suspension: LogitechHardwareSuspension)
    ]()

    private var subscriptions = Set<AnyCancellable>()

    private var activateApplicationObserver: Any?

    var allowsDeviceWork: Bool {
        state.allowsDeviceWork
    }

    func suspendForSleep() {
        switch state {
        case .stopped, .suspending, .suspended, .stopping, .finishing:
            return
        case .running:
            break
        }

        state = .suspending
        pointerDeviceToDevice.values.forEach { $0.releaseSyntheticInputReportButtons() }
        receiverWakeRediscoveryRequests.removeAll()
        receiverWakeHardwareSuspensions.removeAll()
        let request = DeviceManagerSuspensionRequest()
        suspensionRequest = request
        retainedSuspensionRequests[ObjectIdentifier(request)] = request

        let logitechDevices = pointerDeviceToDevice.values.filter {
            $0.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
        }
        for device in logitechDevices {
            guard let suspension = device.suspendLogitechSettings() else {
                continue
            }
            request.logitechSettings[ObjectIdentifier(device)] = (
                WeakRef(device),
                suspension
            )
        }

        startSleepControlsCleanup(devices: logitechDevices, request: request)
    }

    /// Resumes only the exact current sleep owner. A fast wake does not wait
    /// for controls restoration; each monitor records one pending resume and
    /// restarts after its restore-only worker has released the barrier.
    func resumeFromSleep(completion: @escaping () -> Void = {}) {
        switch state {
        case .stopped, .running:
            completion()
            return
        case .stopping, .finishing:
            guard let stopRequest else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            stopRequest.completions.append(completion)
            return
        case .suspending, .suspended:
            break
        }

        guard let request = suspensionRequest,
              request.claimResume()
        else {
            return
        }
        suspensionRequest = nil

        for (identifier, entry) in request.logitechSettings {
            guard let device = entry.device.value else {
                continue
            }
            if shouldMonitorReceiver(device) {
                receiverWakeHardwareSuspensions[identifier] = entry
            } else {
                _ = device.resumeLogitechSettings(from: entry.suspension)
            }
        }

        // A receiver's logical slot may have changed during sleep. Keep the
        // last route only as dormant state so the Hi-Res multiplier remains
        // continuous; no receiver work is admitted until an exact fresh
        // rediscovery completes.
        let receiverDevices = devices.filter(shouldMonitorReceiver)
        let receiverLocationIDs = Set(receiverDevices.compactMap(\.pointerDevice.locationID))
        for locationID in receiverLocationIDs {
            receiverPairedDeviceIdentities.removeValue(forKey: locationID)
            receiverWakeRediscoveryRequests[locationID] = ReceiverRediscoveryRequest()
        }

        lastActiveDeviceId = nil
        lastActiveDeviceRef = nil
        state = .running

        updatePointerSpeed()
        for device in devices {
            if shouldMonitorReceiver(device) {
                receiverMonitor.startMonitoring(device: device)
                if let locationID = device.pointerDevice.locationID,
                   let rediscovery = receiverWakeRediscoveryRequests[locationID] {
                    receiverMonitor.requestRediscovery(device: device, request: rediscovery)
                }
            } else if device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID {
                device.logitechSettingsReconciler.reapplyAfterWake(configuredLogitechDeviceSettings(for: device))
                device.resumeLogitechControlsAfterSleep()
            }
        }
        completion()
    }

    private func startSleepControlsCleanup(
        devices: [Device],
        request: DeviceManagerSuspensionRequest
    ) {
        let deadline = Date().addingTimeInterval(Self.sleepControlsTeardownTimeout)
        let group = DispatchGroup()
        let cleanup = BoundedCleanupRequest(
            timeout: Self.sleepControlsTeardownTimeout,
            onTimeout: {
                os_log(
                    "Timed out restoring Logitech controls for sleep",
                    log: Self.log,
                    type: .error
                )
            },
            completion: { [weak self, weak request] _ in
                guard let self, let request else {
                    return
                }
                request.controlsCleanup = nil
                retainedSuspensionRequests.removeValue(forKey: ObjectIdentifier(request))
                guard suspensionRequest === request, state == .suspending else {
                    return
                }
                state = .suspended
            }
        )
        request.controlsCleanup = cleanup
        let authorization = cleanup.authorizationToken

        for device in devices {
            group.enter()
            device.stopLogitechControlsMonitoringForSleep(
                authorization: authorization,
                deadline: deadline
            ) {
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .utility)) { [weak cleanup] in
            cleanup?.complete()
        }
    }

    private func supersedeSuspensionRequestsForTerminalStop() {
        receiverWakeRediscoveryRequests.removeAll()
        receiverWakeHardwareSuspensions.removeAll()
        let activeRequest = suspensionRequest
        suspensionRequest = nil
        var requests = Array(retainedSuspensionRequests.values)
        if let activeRequest,
           retainedSuspensionRequests[ObjectIdentifier(activeRequest)] == nil {
            requests.append(activeRequest)
        }
        for request in requests {
            request.supersede()
            request.controlsCleanup?.complete()
        }
    }

    func stop(
        logitechTeardownPolicy: DeviceManagerLogitechTeardownPolicy = .restore,
        completion: (() -> Void)? = nil
    ) {
        let requestedIntent = DeviceManagerStopIntent(logitechTeardownPolicy: logitechTeardownPolicy)
        switch state {
        case .stopped:
            if let completion {
                if Thread.isMainThread {
                    completion()
                } else {
                    DispatchQueue.main.async(execute: completion)
                }
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
        case .running, .suspending, .suspended:
            state = .stopping
            let request = DeviceManagerStopRequest(intent: requestedIntent)
            if let completion {
                request.completions.append(completion)
            }
            stopRequest = request
        }

        pointerDeviceToDevice.values.forEach { $0.releaseSyntheticInputReportButtons() }
        supersedeSuspensionRequestsForTerminalStop()

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

        startTerminalLogitechRestore(devices: devices, request: request, start: start)
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
        let cleanupAuthorization = cleanup.authorizationToken

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
            startTerminalLogitechRestore(
                for: device,
                deadline: deadline,
                authorization: cleanupAuthorization
            ) {
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
            // Workers run outside the main actor. Their sole admission is the
            // request-owned token, which is revoked before timeout delivery;
            // main-confined request identities remain checked only by main
            // completion callbacks.
            let restoreIsCurrent = { cleanupAuthorization.shouldContinue }
            let validationGroup = DispatchGroup()

            for device in devices {
                guard let expectedRoute = device.logitechReceiverRouteSnapshot,
                      LogitechStableSerial.normalize(expectedRoute.identity.serialNumber) != nil
                else {
                    // Receiver topology and product metadata are not a device
                    // identity. Without a stable logical-device serial there
                    // is no safe way to distinguish a same-slot replacement,
                    // so terminal writes must fail closed.
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
                              fresh: freshIdentity
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
                    self.startTerminalLogitechRestore(
                        for: device,
                        deadline: deadline,
                        authorization: cleanupAuthorization
                    ) {
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
        authorization: CancellationToken,
        completion: @escaping () -> Void
    ) {
        guard authorization.shouldContinue else {
            completion()
            return
        }
        let group = DispatchGroup()
        group.enter()
        device.restorePendingLogitechControlsForTeardown(
            authorization: authorization,
            deadline: deadline
        ) {
            group.leave()
        }

        group.enter()
        device.restoreLogitechSettingsForTeardown(
            deadline: deadline,
            until: { authorization.shouldContinue }
        ) { restored in
            if !restored, authorization.shouldContinue, Date() < deadline {
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
        fresh: ReceiverLogicalDeviceIdentity
    ) -> Bool {
        guard let expectedSerial = LogitechStableSerial.normalize(expected.serialNumber) else {
            return false
        }
        return LogitechStableSerial.normalize(fresh.serialNumber) == expectedSerial
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
        request.terminalLogitechCleanup = nil
        completions.forEach { $0() }
    }

    func start() {
        guard state == .stopped else {
            return
        }
        state = .running
        receiverWakeRediscoveryRequests.removeAll()
        receiverWakeHardwareSuspensions.removeAll()

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
        guard state.allowsDeviceTopology else {
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

        // PointerKit emits an addition only once per observation lifetime.
        // Keep devices that appear while suspended, then configure them when
        // the exact sleep owner resumes.
        guard allowsDeviceWork else {
            if device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
               let request = suspensionRequest,
               let suspension = device.suspendLogitechSettings() {
                request.logitechSettings[ObjectIdentifier(device)] = (
                    WeakRef(device),
                    suspension
                )
            }
            return
        }

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
                receiverWakeRediscoveryRequests.removeValue(forKey: locationID)
            }
        }

        receiverWakeHardwareSuspensions.removeValue(forKey: ObjectIdentifier(device))
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

        guard updateLogitechReceiverDiscovery(for: device).isReady else {
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

    private func reapplyLogitechDeviceSettings(for device: Device) {
        guard state == .running,
              device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID else {
            return
        }

        guard updateLogitechReceiverDiscovery(for: device).isReady else {
            if shouldMonitorReceiver(device) {
                requestReceiverRediscovery(for: device)
            }
            return
        }

        device.logitechSettingsReconciler.reapply(configuredLogitechDeviceSettings(for: device))
    }

    /// `isReady` remains false for a monitored receiver until discovery has
    /// identified a unique pointing-device slot. Direct devices are ready
    /// immediately; the session update is the sole target-change authority.
    @discardableResult
    private func updateLogitechReceiverDiscovery(
        for device: Device
    ) -> (isReady: Bool, update: LogitechDeviceSession.DiscoveryUpdate?) {
        guard shouldMonitorReceiver(device) else {
            return (true, device.updateLogitechReceiverDiscovery(nil))
        }

        guard let locationID = device.pointerDevice.locationID else {
            return (false, nil)
        }
        guard receiverWakeRediscoveryRequests[locationID] == nil else {
            return (false, nil)
        }
        guard let identities = receiverPairedDeviceIdentities[locationID] else {
            return (false, device.updateLogitechReceiverDiscovery(nil))
        }

        let route = LogitechReceiverRouteResolver.resolve(
            for: device.pointerDevice,
            identities: identities
        )
        let update = device.updateLogitechReceiverDiscovery(.init(
            identities: identities,
            route: route
        ))
        return (route != nil, update)
    }

    private func requestReceiverRediscovery(for device: Device) {
        guard let locationID = device.pointerDevice.locationID else {
            return
        }
        if let wakeRequest = receiverWakeRediscoveryRequests[locationID] {
            receiverMonitor.requestRediscovery(device: device, request: wakeRequest)
        } else {
            receiverMonitor.requestRediscovery(device: device)
        }
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

    private func receiverPointingDevicesChanged(
        locationID: Int,
        publication: ReceiverDiscoveryPublication
    ) {
        let identities = publication.identities
        guard state.allowsDeviceTopology,
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

        receiverPairedDeviceIdentities[locationID] = identities

        let expectedWakeRequest = receiverWakeRediscoveryRequests[locationID]
        let completedWakeRediscovery = expectedWakeRequest != nil
            && publication.rediscoveryRequest === expectedWakeRequest
        if completedWakeRediscovery {
            receiverWakeRediscoveryRequests.removeValue(forKey: locationID)
        }

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

        for (_, device) in pointerDeviceToDevice where device.pointerDevice.locationID == locationID {
            // Publications from before the exact wake request remain useful
            // topology, but cannot reopen the stale receiver route or hardware
            // admission.
            guard receiverWakeRediscoveryRequests[locationID] == nil else {
                continue
            }

            let previousRoute = device.logitechReceiverRouteSnapshot
            let discovery = updateLogitechReceiverDiscovery(for: device)
            let deviceIdentifier = ObjectIdentifier(device)
            let wakeRecoveryPending = receiverWakeHardwareSuspensions[deviceIdentifier] != nil
            let resumedAfterWake: Bool
            if discovery.isReady,
               let suspension = receiverWakeHardwareSuspensions[deviceIdentifier] {
                resumedAfterWake = device.resumeLogitechSettings(from: suspension.suspension)
                if resumedAfterWake {
                    receiverWakeHardwareSuspensions.removeValue(forKey: deviceIdentifier)
                }
            } else {
                resumedAfterWake = false
            }

            guard allowsDeviceWork else {
                continue
            }
            guard discovery.isReady, let route = device.logitechReceiverRouteSnapshot else {
                if !wakeRecoveryPending, !identities.isEmpty {
                    device.requestLogitechControlsForcedReconfiguration()
                }
                continue
            }

            let identityChanged = previousRoute != route
            if resumedAfterWake {
                device.logitechSettingsReconciler.reapplyAfterWake(configuredLogitechDeviceSettings(for: device))
                device.resumeLogitechControlsAfterSleep()
            } else if discovery.update?.hardwareTargetChanged == true {
                device.logitechSettingsReconciler.reapply(configuredLogitechDeviceSettings(for: device))
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
