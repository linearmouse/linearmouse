// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

final class ReceiverMonitor {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ReceiverMonitor")
    static let initialDiscoveryTimeout: TimeInterval = 3
    static let refreshInterval: TimeInterval = 15

    private let provider = LogitechHIDPPDeviceMetadataProvider()
    private var contexts = [Int: ReceiverContext]()

    var onPointingDevicesChanged: ((Int, [ReceiverLogicalDeviceIdentity]) -> Void)?

    func startMonitoring(device: Device) {
        guard let locationID = device.pointerDevice.locationID else {
            return
        }

        guard contexts[locationID] == nil else {
            return
        }

        let context = ReceiverContext(device: device, locationID: locationID, provider: provider)
        context.onDiscoveryTimedOut = { [weak self, weak context] in
            guard let self,
                  let context,
                  self.contexts[locationID] === context
            else {
                return
            }

            self.onPointingDevicesChanged?(locationID, [])
        }
        context.onSlotsChanged = { [weak self, weak context] identities in
            guard let self,
                  let context,
                  self.contexts[locationID] === context
            else {
                return
            }

            self.onPointingDevicesChanged?(locationID, identities)
        }
        contexts[locationID] = context
        context.start()

        os_log("Started receiver monitor for %{public}@", log: Self.log, type: .info, String(describing: device))
    }

    func stopMonitoring(device: Device) {
        guard let locationID = device.pointerDevice.locationID,
              let context = contexts.removeValue(forKey: locationID)
        else {
            return
        }

        context.stop()
    }
}

struct ReceiverSlotStateStore {
    enum SlotPresenceState {
        case unknown
        case connected
        case disconnected
    }

    private var pairedIdentitiesBySlot = [UInt8: ReceiverLogicalDeviceIdentity]()
    private var slotPresenceBySlot = [UInt8: SlotPresenceState]()

    mutating func reset() {
        pairedIdentitiesBySlot = [:]
        slotPresenceBySlot = [:]
    }

    mutating func mergeDiscovery(_ discovery: LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery) {
        let latestIdentitiesBySlot = Dictionary(uniqueKeysWithValues: discovery.identities.map {
            ($0.slot, $0)
        })
        let previousIdentitiesBySlot = pairedIdentitiesBySlot

        for slot in pairedIdentitiesBySlot.keys where latestIdentitiesBySlot[slot] == nil {
            pairedIdentitiesBySlot.removeValue(forKey: slot)
            slotPresenceBySlot.removeValue(forKey: slot)
        }

        for (slot, identity) in latestIdentitiesBySlot {
            pairedIdentitiesBySlot[slot] = identity
            if slotPresenceBySlot[slot] == nil {
                slotPresenceBySlot[slot] = .unknown
            }
        }

        mergeConnectionSnapshots(discovery.connectionSnapshots)

        for slot in discovery.liveReachableSlots {
            if slotPresenceBySlot[slot] != .connected {
                slotPresenceBySlot[slot] = .connected
            }
        }

        for (slot, identity) in latestIdentitiesBySlot where discovery.connectionSnapshots[slot] == nil {
            guard slotPresenceBySlot[slot] == .disconnected,
                  previousIdentitiesBySlot[slot]?.batteryLevel == nil,
                  identity.batteryLevel != nil,
                  !discovery.liveReachableSlots.contains(slot)
            else {
                continue
            }

            slotPresenceBySlot[slot] = .connected
        }
    }

    mutating func mergeConnectionSnapshots(
        _ newSnapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot]
    ) {
        for (slot, snapshot) in newSnapshots {
            slotPresenceBySlot[slot] = snapshot.isConnected ? .connected : .disconnected
        }
    }

    mutating func updateSlotIdentity(_ identity: ReceiverLogicalDeviceIdentity) {
        pairedIdentitiesBySlot[identity.slot] = identity
        slotPresenceBySlot[identity.slot] = .connected
    }

    func needsIdentityRefresh(slot: UInt8) -> Bool {
        pairedIdentitiesBySlot[slot] == nil
    }

    func currentPublishedIdentities() -> [ReceiverLogicalDeviceIdentity] {
        pairedIdentitiesBySlot.keys.sorted().compactMap { slot in
            guard let identity = pairedIdentitiesBySlot[slot] else {
                return nil
            }

            return slotPresenceBySlot[slot] == .disconnected ? nil : identity
        }
    }
}

private final class ReceiverContext {
    let device: Device
    private let locationID: Int
    private let provider: LogitechHIDPPDeviceMetadataProvider
    private var workerThread: Thread?
    private var isRunning = false
    private let stateLock = NSLock()
    private var lastPublishedIdentities = [ReceiverLogicalDeviceIdentity]()
    private var stateStore = ReceiverSlotStateStore()

    var onDiscoveryTimedOut: (() -> Void)?
    var onSlotsChanged: (([ReceiverLogicalDeviceIdentity]) -> Void)?
    init(device: Device, locationID: Int, provider: LogitechHIDPPDeviceMetadataProvider) {
        self.device = device
        self.locationID = locationID
        self.provider = provider
    }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isRunning else {
            return
        }
        isRunning = true
        lastPublishedIdentities = []
        stateStore.reset()

        let thread = Thread { [weak self] in
            self?.workerMain()
        }
        thread.name = "linearmouse.receiver-monitor.\(locationID)"
        workerThread = thread
        thread.start()
    }

    func stop() {
        stateLock.lock()
        isRunning = false
        let thread = workerThread
        workerThread = nil
        stateLock.unlock()

        thread?.cancel()
    }

    private func workerMain() {
        let initialDeadline = Date().addingTimeInterval(ReceiverMonitor.initialDiscoveryTimeout)
        var hasPublishedInitialState = false
        var receiverChannel: LogitechReceiverChannel?
        var hasCompletedInitialDiscovery = false

        while shouldContinueRunning() {
            if receiverChannel == nil {
                receiverChannel = provider.openReceiverChannel(for: device.pointerDevice)
                hasCompletedInitialDiscovery = false
            }

            guard let receiverChannel else {
                os_log(
                    "Receiver monitor is waiting for channel: locationID=%{public}d device=%{public}@",
                    log: ReceiverMonitor.log,
                    type: .info,
                    locationID,
                    String(describing: device)
                )

                if !hasPublishedInitialState, Date() >= initialDeadline {
                    DispatchQueue.main.async { [weak self] in
                        self?.onDiscoveryTimedOut?()
                    }
                    hasPublishedInitialState = true
                }

                CFRunLoopRunInMode(.defaultMode, 0.5, true)
                continue
            }

            // Full discovery only once per channel open
            if !hasCompletedInitialDiscovery {
                let discovery = provider.receiverPointingDeviceDiscovery(
                    for: device.pointerDevice, using: receiverChannel
                )
                mergeDiscovery(discovery)
                hasCompletedInitialDiscovery = true

                let identities = currentPublishedIdentities()
                let identitiesDescription = identities.map { identity in
                    let battery = identity.batteryLevel.map(String.init) ?? "(nil)"
                    return "slot=\(identity.slot) name=\(identity.name) battery=\(battery)"
                }
                .joined(separator: ", ")

                os_log(
                    "Receiver initial discovery completed: locationID=%{public}d count=%{public}u identities=%{public}@",
                    log: ReceiverMonitor.log,
                    type: .info,
                    locationID,
                    UInt32(identities.count),
                    identitiesDescription
                )

                if identities != lastPublishedIdentities {
                    publish(identities)
                    hasPublishedInitialState = true
                } else if !hasPublishedInitialState, !identities.isEmpty {
                    publish(identities)
                    hasPublishedInitialState = true
                } else if !hasPublishedInitialState, Date() >= initialDeadline {
                    os_log(
                        "Receiver logical discovery timed out: locationID=%{public}d device=%{public}@",
                        log: ReceiverMonitor.log,
                        type: .info,
                        locationID,
                        String(describing: device)
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?.onDiscoveryTimedOut?()
                    }
                    hasPublishedInitialState = true
                }
            }

            // Wait for connection events (event-driven, no periodic rescan)
            let connectionSnapshots = provider.waitForReceiverConnectionChange(
                using: receiverChannel,
                timeout: ReceiverMonitor.refreshInterval
            ) { [weak self] in
                self?.shouldContinueRunning() ?? false
            }

            if !shouldContinueRunning() {
                break
            }

            guard !connectionSnapshots.isEmpty else {
                // Timeout with no events — just continue waiting
                continue
            }

            mergeConnectionSnapshots(connectionSnapshots)

            // For newly connected devices, read their identity info
            for (slot, snapshot) in connectionSnapshots where snapshot.isConnected {
                if needsIdentityRefresh(slot: slot) {
                    refreshSlotIdentity(
                        slot: slot,
                        connectionSnapshot: snapshot,
                        using: receiverChannel
                    )
                }
            }

            let snapshotDescription = connectionSnapshots.keys
                .sorted()
                .compactMap { slot -> String? in
                    guard let snapshot = connectionSnapshots[slot] else {
                        return nil
                    }

                    return "slot=\(slot) connected=\(snapshot.isConnected)"
                }
                .joined(separator: ", ")

            os_log(
                "Receiver connection change detected: locationID=%{public}d device=%{public}@ snapshots=%{public}@",
                log: ReceiverMonitor.log,
                type: .info,
                locationID,
                String(describing: device),
                snapshotDescription
            )

            let identities = currentPublishedIdentities()
            if identities != lastPublishedIdentities {
                publish(identities)
            }
        }
    }

    private func publish(_ identities: [ReceiverLogicalDeviceIdentity]) {
        lastPublishedIdentities = identities

        let identitiesDescription = identities.map { identity in
            let battery = identity.batteryLevel.map(String.init) ?? "(nil)"
            return "slot=\(identity.slot) name=\(identity.name) battery=\(battery)"
        }
        .joined(separator: ", ")

        os_log(
            "Receiver logical discovery updated: locationID=%{public}d identities=%{public}@",
            log: ReceiverMonitor.log,
            type: .info,
            locationID,
            identitiesDescription
        )

        DispatchQueue.main.async { [weak self] in
            self?.onSlotsChanged?(identities)
        }
    }

    private func shouldContinueRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }

    private func mergeDiscovery(_ discovery: LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery) {
        stateLock.lock()
        defer { stateLock.unlock() }
        stateStore.mergeDiscovery(discovery)
    }

    private func mergeConnectionSnapshots(
        _ newSnapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot]
    ) {
        guard !newSnapshots.isEmpty else {
            return
        }

        stateLock.lock()
        stateStore.mergeConnectionSnapshots(newSnapshots)
        stateLock.unlock()
    }

    private func refreshSlotIdentity(
        slot: UInt8,
        connectionSnapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot?,
        using receiverChannel: LogitechReceiverChannel
    ) {
        guard let identity = provider.receiverSlotIdentity(
            for: device.pointerDevice,
            slot: slot,
            connectionSnapshot: connectionSnapshot,
            using: receiverChannel
        ) else {
            return
        }

        stateLock.lock()
        stateStore.updateSlotIdentity(identity)
        stateLock.unlock()

        os_log(
            "Refreshed slot identity: locationID=%{public}d slot=%{public}u name=%{public}@ battery=%{public}@",
            log: ReceiverMonitor.log,
            type: .info,
            locationID,
            slot,
            identity.name,
            identity.batteryLevel.map(String.init) ?? "(nil)"
        )
    }

    private func needsIdentityRefresh(slot: UInt8) -> Bool {
        stateLock.lock()
        let needs = stateStore.needsIdentityRefresh(slot: slot)
        stateLock.unlock()
        return needs
    }

    private func currentPublishedIdentities() -> [ReceiverLogicalDeviceIdentity] {
        stateLock.lock()
        let identities = stateStore.currentPublishedIdentities()
        stateLock.unlock()
        return identities
    }
}
