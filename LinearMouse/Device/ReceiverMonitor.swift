// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

final class ReceiverMonitor {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ReceiverMonitor")
    static let initialDiscoveryTimeout: TimeInterval = 3
    static let channelOpenRetryInterval: TimeInterval = 0.5
    static let maximumDiscoveryRetryInterval: TimeInterval = 15
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

    func requestRediscovery(device: Device) {
        guard let locationID = device.pointerDevice.locationID else {
            return
        }

        contexts[locationID]?.requestRediscovery()
    }
}

struct ReceiverSlotStateStore {
    struct DiscoveryMergeResult {
        let inventoryComplete: Bool
    }

    enum SlotPresenceState {
        case unknown
        case connected
        case disconnected
    }

    private var pairedIdentitiesBySlot = [UInt8: ReceiverLogicalDeviceIdentity]()
    private var slotPresenceBySlot = [UInt8: SlotPresenceState]()
    private var slotsRequiringPointingIdentity = Set<UInt8>()

    mutating func reset() {
        pairedIdentitiesBySlot = [:]
        slotPresenceBySlot = [:]
        slotsRequiringPointingIdentity = []
    }

    /// A receiver channel is no longer trustworthy. Its pairing cache must not
    /// keep a logical device routable while a replacement channel is opened.
    mutating func invalidateChannel() {
        reset()
    }

    mutating func mergeDiscovery(
        _ discovery: LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery
    ) -> DiscoveryMergeResult {
        let latestIdentitiesBySlot = Dictionary(uniqueKeysWithValues: discovery.identities.map {
            ($0.slot, $0)
        })
        pairedIdentitiesBySlot = latestIdentitiesBySlot
        slotPresenceBySlot = [:]
        slotsRequiringPointingIdentity = []

        for (slot, snapshot) in discovery.connectionSnapshots {
            slotPresenceBySlot[slot] = snapshot.isConnected ? .connected : .disconnected
        }
        for slot in discovery.liveReachableSlots {
            slotPresenceBySlot[slot] = .connected
        }

        let connectedSlots = Set(discovery.connectionSnapshots.compactMap { slot, snapshot in
            snapshot.isConnected ? slot : nil
        }).union(discovery.liveReachableSlots)
        let slotKinds = Dictionary(uniqueKeysWithValues: connectedSlots.compactMap { slot -> (
            UInt8,
            ReceiverLogicalDeviceKind
        )? in
            let rawKind = discovery.connectionSnapshots[slot]?.kind ?? discovery.observedSlotKinds[slot]
            guard let rawKind,
                  let kind = ReceiverLogicalDeviceKind(rawValue: rawKind)
            else {
                return nil
            }
            return (slot, kind)
        })

        for slot in connectedSlots {
            guard let kind = slotKinds[slot] else {
                continue
            }
            if kind.isPointingDevice, latestIdentitiesBySlot[slot] == nil {
                slotsRequiringPointingIdentity.insert(slot)
            }
        }

        let inventoryComplete = discovery.inventoryAvailable
            && discovery.expectedConnectedDeviceCount != nil
            && connectedSlots.count == discovery.expectedConnectedDeviceCount
            && slotKinds.count == connectedSlots.count
            && !hasConnectedSlotMissingIdentity
        return .init(inventoryComplete: inventoryComplete)
    }

    mutating func mergeConnectionSnapshots(
        _ newSnapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot]
    ) {
        for (slot, snapshot) in newSnapshots {
            let newPresence: SlotPresenceState = snapshot.isConnected ? .connected : .disconnected
            let oldPresence = slotPresenceBySlot[slot]
            let previousIdentity = pairedIdentitiesBySlot[slot]
            slotPresenceBySlot[slot] = newPresence

            guard newPresence == .connected else {
                slotsRequiringPointingIdentity.remove(slot)
                continue
            }

            let reportedKind = snapshot.kind.flatMap(ReceiverLogicalDeviceKind.init(rawValue:))
            if let reportedKind, !reportedKind.isPointingDevice {
                // An explicitly non-pointing device cannot inherit a stale
                // mouse identity or hold up pointing-device discovery.
                pairedIdentitiesBySlot.removeValue(forKey: slot)
                slotsRequiringPointingIdentity.remove(slot)
                continue
            }

            // Clear stale identity when a device reconnects to a slot,
            // so the next needsIdentityRefresh check will trigger a refresh.
            if oldPresence == .disconnected {
                pairedIdentitiesBySlot.removeValue(forKey: slot)
            }

            if reportedKind?.isPointingDevice == true
                || oldPresence == .disconnected && previousIdentity != nil {
                slotsRequiringPointingIdentity.insert(slot)
            }
        }
    }

    mutating func updateSlotIdentity(_ identity: ReceiverLogicalDeviceIdentity) {
        pairedIdentitiesBySlot[identity.slot] = identity
        slotPresenceBySlot[identity.slot] = .connected
        slotsRequiringPointingIdentity.remove(identity.slot)
    }

    func needsIdentityRefresh(slot: UInt8) -> Bool {
        pairedIdentitiesBySlot[slot] == nil
    }

    /// A connected slot without an identity cannot be used as a stable route.
    /// Discovery must retry until its transient identity read succeeds.
    var hasConnectedSlotMissingIdentity: Bool {
        slotsRequiringPointingIdentity.contains { slot in
            slotPresenceBySlot[slot] == .connected && pairedIdentitiesBySlot[slot] == nil
        }
    }

    func currentPublishedIdentities() -> [ReceiverLogicalDeviceIdentity] {
        pairedIdentitiesBySlot.keys.sorted().compactMap { slot in
            guard let identity = pairedIdentitiesBySlot[slot] else {
                return nil
            }

            return slotPresenceBySlot[slot] == .connected ? identity : nil
        }
    }
}

private final class ReceiverContext {
    private enum DiscoveryState {
        case pending
        case ready
    }

    let device: Device
    private let locationID: Int
    private let provider: LogitechHIDPPDeviceMetadataProvider
    private var workerThread: Thread?
    private var isRunning = false
    private let stateLock = NSLock()
    private var lastPublishedIdentities = [ReceiverLogicalDeviceIdentity]()
    private var stateStore = ReceiverSlotStateStore()
    private var currentChannel: LogitechReceiverChannel?
    private var rediscoveryRequested = false
    private let retrySemaphore = DispatchSemaphore(value: 0)

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
        rediscoveryRequested = false
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
        let channel = currentChannel
        workerThread = nil
        stateLock.unlock()

        channel?.wake()
        retrySemaphore.signal()
        thread?.cancel()
    }

    func requestRediscovery() {
        stateLock.lock()
        guard isRunning else {
            stateLock.unlock()
            return
        }

        rediscoveryRequested = true
        let channel = currentChannel
        stateLock.unlock()

        channel?.wake()
        retrySemaphore.signal()
    }

    private func workerMain() {
        let initialDeadline = Date().addingTimeInterval(ReceiverMonitor.initialDiscoveryTimeout)
        var hasPublishedInitialState = false
        var hasLoggedMissingChannel = false
        var discoveryState = DiscoveryState.pending
        var discoveryBackoff = ExponentialBackoff(
            initialDelay: ReceiverMonitor.channelOpenRetryInterval,
            maximumDelay: ReceiverMonitor.maximumDiscoveryRetryInterval
        )
        defer {
            setCurrentChannel(nil)
            markStopped()
        }

        while shouldContinueRunning() {
            if consumeRediscoveryRequest() {
                discoveryState = .pending
                discoveryBackoff.reset()
            }

            if currentChannelSnapshot() == nil {
                let channel = provider.openReceiverChannel(for: device.pointerDevice)
                setCurrentChannel(channel)

                if !shouldContinueRunning() {
                    channel?.wake()
                    break
                }
            }

            guard let receiverChannel = currentChannelSnapshot() else {
                if !hasLoggedMissingChannel {
                    os_log(
                        "Receiver channel is unavailable, will retry briefly: locationID=%{public}d device=%{public}@",
                        log: ReceiverMonitor.log,
                        type: .info,
                        locationID,
                        String(describing: device)
                    )
                    hasLoggedMissingChannel = true
                }

                if !hasPublishedInitialState, Date() >= initialDeadline {
                    DispatchQueue.main.async { [weak self] in
                        self?.onDiscoveryTimedOut?()
                    }
                    hasPublishedInitialState = true
                }

                waitBeforeRetryingDiscovery(after: discoveryBackoff.nextDelay(), until: initialDeadline)

                continue
            }
            hasLoggedMissingChannel = false

            if LogitechHIDPPDeviceMetadataProvider.receiverProtocolFamily(
                vendorID: device.pointerDevice.vendorID,
                productID: device.pointerDevice.productID,
                transport: device.pointerDevice.transport
            ) == .lightspeed,
                !provider.receiverChannelIsReachable(for: device.pointerDevice, using: receiverChannel) {
                os_log(
                    "Lightspeed receiver did not respond to the HID++ capability probe, retrying: locationID=%{public}d device=%{public}@",
                    log: ReceiverMonitor.log,
                    type: .info,
                    locationID,
                    String(describing: device)
                )
                invalidateCurrentChannel(receiverChannel)
                discoveryState = .pending
                discoveryBackoff.reset()
                if !hasPublishedInitialState, Date() >= initialDeadline {
                    DispatchQueue.main.async { [weak self] in
                        self?.onDiscoveryTimedOut?()
                    }
                    hasPublishedInitialState = true
                }
                waitBeforeRetryingDiscovery(after: discoveryBackoff.nextDelay(), until: initialDeadline)
                continue
            }

            // A receiver has no usable route until full discovery succeeds.
            if case .pending = discoveryState {
                let discovery = provider.receiverPointingDeviceDiscovery(
                    for: device.pointerDevice, using: receiverChannel
                )
                let mergeResult = mergeDiscovery(discovery)

                let identities = currentPublishedIdentities()
                if !mergeResult.inventoryComplete {
                    publishUnavailable()
                    os_log(
                        "Receiver inventory is incomplete, retrying: locationID=%{public}d device=%{public}@",
                        log: ReceiverMonitor.log,
                        type: .info,
                        locationID,
                        String(describing: device)
                    )
                    if !hasPublishedInitialState, Date() >= initialDeadline {
                        os_log(
                            "Receiver logical discovery timed out; background retries will continue: locationID=%{public}d device=%{public}@",
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

                    waitBeforeRetryingDiscovery(after: discoveryBackoff.nextDelay(), until: initialDeadline)
                    continue
                }

                discoveryState = .ready
                discoveryBackoff.reset()
                _ = consumeRediscoveryRequest()
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
                } else if !hasPublishedInitialState {
                    publish(identities)
                    hasPublishedInitialState = true
                }
            }

            // Wait for connection events (event-driven, no periodic rescan)
            let connectionSnapshots = provider.waitForReceiverConnectionChange(
                for: device.pointerDevice,
                using: receiverChannel,
                timeout: ReceiverMonitor.refreshInterval
            ) { [weak self] in
                self?.shouldContinueWaitingForNotifications() ?? false
            }

            if !shouldContinueRunning() {
                break
            }

            if hasRediscoveryRequest() {
                continue
            }

            guard !connectionSnapshots.isEmpty else {
                // Timeout with no events — verify channel is still alive
                if !provider.receiverChannelIsReachable(for: device.pointerDevice, using: receiverChannel) {
                    os_log(
                        "Receiver channel appears dead, will reopen: locationID=%{public}d device=%{public}@",
                        log: ReceiverMonitor.log,
                        type: .info,
                        locationID,
                        String(describing: device)
                    )
                    invalidateCurrentChannel(receiverChannel)
                    discoveryState = .pending
                    discoveryBackoff.reset()
                }
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
            let needsIdentityRefresh = hasConnectedSlotMissingIdentity()
            if needsIdentityRefresh {
                // A reconnect identity read can fail transiently. Re-enter the
                // existing pending-discovery path, which retries with backoff
                // instead of keeping this incomplete slot in the ready state.
                discoveryState = .pending
                discoveryBackoff.reset()
                publishUnavailable()
            }
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

    private func publishUnavailable() {
        guard !lastPublishedIdentities.isEmpty else {
            return
        }

        publish([])
    }

    private func shouldContinueRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }

    private func markStopped() {
        stateLock.lock()
        isRunning = false
        workerThread = nil
        stateLock.unlock()
    }

    private func hasRediscoveryRequest() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return rediscoveryRequested
    }

    private func shouldContinueWaitingForNotifications() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning && !rediscoveryRequested
    }

    private func consumeRediscoveryRequest() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        let requested = rediscoveryRequested
        rediscoveryRequested = false
        return requested
    }

    private func waitBeforeRetryingDiscovery(
        after interval: TimeInterval,
        until deadline: Date? = nil
    ) {
        let retryDelay: TimeInterval
        if let deadline {
            let remaining = deadline.timeIntervalSinceNow
            retryDelay = remaining > 0 ? min(interval, remaining) : interval
        } else {
            retryDelay = interval
        }

        guard retryDelay > 0 else {
            return
        }

        _ = retrySemaphore.wait(timeout: .now() + retryDelay)
    }

    private func setCurrentChannel(_ channel: LogitechReceiverChannel?) {
        stateLock.lock()
        currentChannel = channel
        stateLock.unlock()
    }

    private func invalidateCurrentChannel(_ channel: LogitechReceiverChannel) {
        setCurrentChannel(nil)
        LogitechReceiverChannel.discardSharedChannel(locationID: locationID, matching: channel)
        stateStore.invalidateChannel()
        publish([])
    }

    private func currentChannelSnapshot() -> LogitechReceiverChannel? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentChannel
    }

    private func mergeDiscovery(
        _ discovery: LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery
    ) -> ReceiverSlotStateStore.DiscoveryMergeResult {
        stateStore.mergeDiscovery(discovery)
    }

    private func mergeConnectionSnapshots(
        _ newSnapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot]
    ) {
        guard !newSnapshots.isEmpty else {
            return
        }

        stateStore.mergeConnectionSnapshots(newSnapshots)
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

        stateStore.updateSlotIdentity(identity)

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
        stateStore.needsIdentityRefresh(slot: slot)
    }

    private func hasConnectedSlotMissingIdentity() -> Bool {
        stateStore.hasConnectedSlotMissingIdentity
    }

    private func currentPublishedIdentities() -> [ReceiverLogicalDeviceIdentity] {
        stateStore.currentPublishedIdentities()
    }
}
