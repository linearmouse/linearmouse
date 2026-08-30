// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

/// Concrete ownership of one explicit receiver rediscovery. A wake accepts a
/// route only when the publication carries the exact request it started.
final class ReceiverRediscoveryRequest {}

struct ReceiverDiscoveryPublication {
    let identities: [ReceiverLogicalDeviceIdentity]
    let rediscoveryRequest: ReceiverRediscoveryRequest?
}

enum ReceiverConnectionEventPublication {
    static func identities(
        afterEvent identities: [ReceiverLogicalDeviceIdentity],
        hasUnresolvedConnectedSlot: Bool
    ) -> [ReceiverLogicalDeviceIdentity] {
        hasUnresolvedConnectedSlot ? [] : identities
    }
}

enum ReceiverReconnectPublication {
    static func requiresRouteLoss(
        reconnectedSlots: Set<UInt8>,
        snapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot],
        currentIdentities: [ReceiverLogicalDeviceIdentity]
    ) -> Bool {
        reconnectedSlots.contains { slot in
            currentIdentities.contains { $0.slot == slot }
                || ReceiverLogicalDeviceKind(rawValue: snapshots[slot]?.kind ?? 0)?.isPointingDevice == true
        }
    }
}

enum ReceiverPendingDiscoveryDisposition {
    case retryCurrentChannel
    case reopenChannel

    static func resolve(inventoryAvailable: Bool, channelReachable: Bool) -> Self {
        !inventoryAvailable && !channelReachable ? .reopenChannel : .retryCurrentChannel
    }
}

enum ReceiverReadyCountDisposition {
    case stayReady
    case enterPending

    static func resolve(previousCount: Int?, currentCount: Int?) -> Self {
        guard let currentCount else {
            return .stayReady
        }

        return previousCount == currentCount ? .stayReady : .enterPending
    }
}

enum ReceiverWorkerPostCallAdmission {
    struct Admitted<Value> {
        let value: Value
    }

    static func admit<Value>(
        _ operation: () -> Value,
        whileRunning: () -> Bool
    ) -> Admitted<Value>? {
        let value = operation()
        guard whileRunning() else {
            return nil
        }
        return .init(value: value)
    }
}

enum ReceiverWorkerChannelAdoption {
    static func adopt<Channel: AnyObject>(
        _ channel: Channel,
        whileRunning isRunning: Bool,
        currentChannel: inout Channel?
    ) -> Bool {
        guard isRunning, currentChannel == nil else {
            return false
        }
        currentChannel = channel
        return true
    }
}

struct ReceiverMonitorHandoff<Owner: AnyObject, Candidate: AnyObject> {
    private enum Phase {
        case active(owner: Owner, candidate: Candidate)
        case stopping(owner: Owner, stoppedCandidate: Candidate, pending: [Candidate])
    }

    private var phase: Phase?

    /// Returns true only when the caller owns the empty slot and may create a
    /// context immediately. A stopping owner retains the slot until onStopped.
    mutating func requestStart(_ candidate: Candidate) -> Bool {
        switch phase {
        case nil:
            return true
        case .active:
            return false
        case let .stopping(owner, stoppedCandidate, pending):
            let candidates = pending.contains { $0 === candidate }
                ? pending
                : pending + [candidate]
            phase = .stopping(
                owner: owner,
                stoppedCandidate: stoppedCandidate,
                pending: candidates
            )
            return false
        }
    }

    @discardableResult
    mutating func activate(_ owner: Owner, for candidate: Candidate) -> Bool {
        guard phase == nil else {
            return false
        }
        phase = .active(owner: owner, candidate: candidate)
        return true
    }

    /// Transitions an active slot to stopping and returns its owner exactly
    /// once. A stop from a newer lifecycle clears every pending candidate; the
    /// old lifecycle's repeated stop cannot cancel its successor.
    mutating func requestStop(for candidate: Candidate) -> Owner? {
        switch phase {
        case nil:
            return nil
        case let .active(owner, activeCandidate):
            phase = .stopping(
                owner: owner,
                stoppedCandidate: activeCandidate,
                pending: []
            )
            return owner
        case let .stopping(owner, stoppedCandidate, pending):
            if candidate !== stoppedCandidate {
                phase = .stopping(
                    owner: owner,
                    stoppedCandidate: stoppedCandidate,
                    pending: []
                )
            } else {
                phase = .stopping(
                    owner: owner,
                    stoppedCandidate: stoppedCandidate,
                    pending: pending
                )
            }
            return nil
        }
    }

    /// Stops whichever owner currently produces receiver events and discards
    /// every pending replacement. Terminal teardown has already retained the
    /// exact shared channel, so no candidate may restart this location until a
    /// new DeviceManager observation lifetime begins.
    mutating func requestTerminalStop() -> Owner? {
        switch phase {
        case nil:
            return nil
        case let .active(owner, candidate):
            phase = .stopping(
                owner: owner,
                stoppedCandidate: candidate,
                pending: []
            )
            return owner
        case let .stopping(owner, stoppedCandidate, _):
            phase = .stopping(
                owner: owner,
                stoppedCandidate: stoppedCandidate,
                pending: []
            )
            return nil
        }
    }

    /// Releases only the matching stopping owner. The caller may start the
    /// returned live candidate after this transition has made the slot empty.
    mutating func didStop(
        _ owner: Owner,
        candidateIsValid: (Candidate) -> Bool
    ) -> Candidate? {
        guard case let .stopping(currentOwner, _, pending) = phase,
              currentOwner === owner
        else {
            return nil
        }
        phase = nil
        return pending.first(where: candidateIsValid)
    }

    func isActive(_ owner: Owner) -> Bool {
        guard case let .active(currentOwner, _) = phase else {
            return false
        }
        return currentOwner === owner
    }

    var isEmpty: Bool {
        phase == nil
    }

    var activeOwner: Owner? {
        guard case let .active(owner, _) = phase else {
            return nil
        }
        return owner
    }

    var currentOwner: Owner? {
        switch phase {
        case let .active(owner, _), let .stopping(owner, _, _):
            return owner
        case nil:
            return nil
        }
    }
}

final class ReceiverMonitor {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ReceiverMonitor")
    static let initialDiscoveryTimeout: TimeInterval = 3
    static let channelOpenRetryInterval: TimeInterval = 0.5
    static let identityRefreshTimeout: TimeInterval = 0.5
    static let maximumDiscoveryRetryInterval: TimeInterval = 15
    static let refreshInterval: TimeInterval = 15

    private let provider = LogitechHIDPPDeviceMetadataProvider()
    private var handoffs = [Int: ReceiverMonitorHandoff<ReceiverContext, Device>]()
    private var pendingRediscoveryRequests = [Int: ReceiverRediscoveryRequest]()

    var onPointingDevicesChanged: ((Int, ReceiverDiscoveryPublication) -> Void)?

    func startMonitoring(device: Device) {
        guard !device.isRemoved,
              let locationID = device.pointerDevice.locationID else {
            return
        }

        var handoff = handoffs[locationID] ?? .init()
        guard handoff.requestStart(device) else {
            handoffs[locationID] = handoff
            return
        }

        startContext(device: device, locationID: locationID, handoff: &handoff)
        handoffs[locationID] = handoff
    }

    private func startContext(
        device: Device,
        locationID: Int,
        handoff: inout ReceiverMonitorHandoff<ReceiverContext, Device>
    ) {
        let context = ReceiverContext(device: device, locationID: locationID, provider: provider)
        context.onDiscoveryTimedOut = { [weak self, weak context] in
            guard let self,
                  let context,
                  self.handoffs[locationID]?.isActive(context) == true
            else {
                return
            }

            self.onPointingDevicesChanged?(
                locationID,
                .init(identities: [], rediscoveryRequest: nil)
            )
        }
        context.onSlotsChanged = { [weak self, weak context] publication in
            guard let self,
                  let context,
                  self.handoffs[locationID]?.isActive(context) == true
            else {
                return
            }

            if let request = publication.rediscoveryRequest,
               self.pendingRediscoveryRequests[locationID] === request {
                self.pendingRediscoveryRequests.removeValue(forKey: locationID)
            }
            self.onPointingDevicesChanged?(locationID, publication)
        }
        context.onStopped = { [weak self, weak context] in
            guard let self, let context else {
                return
            }
            self.contextDidStop(context, locationID: locationID)
        }
        guard handoff.activate(context, for: device) else {
            return
        }
        context.start()
        if let request = pendingRediscoveryRequests[locationID] {
            context.requestRediscovery(request)
        }

        os_log("Started receiver monitor for %{public}@", log: Self.log, type: .info, String(describing: device))
    }

    func stopMonitoring(device: Device) {
        guard let locationID = device.pointerDevice.locationID else {
            return
        }
        guard var handoff = handoffs[locationID] else {
            pendingRediscoveryRequests.removeValue(forKey: locationID)
            return
        }

        let context = handoff.requestStop(for: device)
        handoffs[locationID] = handoff
        context?.stop()
    }

    func requestRediscovery(
        device: Device,
        request: ReceiverRediscoveryRequest = .init()
    ) {
        guard let locationID = device.pointerDevice.locationID else {
            return
        }

        guard pendingRediscoveryRequests[locationID] !== request else {
            return
        }
        pendingRediscoveryRequests[locationID] = request
        handoffs[locationID]?.activeOwner?.requestRediscovery(request)
    }

    /// Freezes receiver-channel mutation first, then stops every monitor
    /// producer. Each returned lease retains an existing channel or owns the
    /// sole right to open its replacement on the background cleanup worker.
    /// Callers must keep the leases alive through the whole hardware cleanup
    /// and finish them on both success and timeout.
    func beginTerminalTeardown(
        locationIDs requestedLocationIDs: Set<Int>
    ) -> [LogitechReceiverChannel.TerminalTeardown] {
        let locationIDs = requestedLocationIDs.union(handoffs.keys).sorted()
        for locationID in locationIDs {
            pendingRediscoveryRequests.removeValue(forKey: locationID)
        }
        let teardowns = locationIDs.compactMap { locationID in
            let notificationOwnershipSession = handoffs[locationID]?
                .currentOwner?
                .notificationOwnershipSession
                ?? ReceiverNotificationOwnershipSession()
            return LogitechReceiverChannel.beginTerminalTeardown(
                locationID: locationID,
                notificationOwnershipSession: notificationOwnershipSession
            )
        }

        var contexts = [ReceiverContext]()
        for locationID in locationIDs {
            guard var handoff = handoffs[locationID] else {
                continue
            }
            if let context = handoff.requestTerminalStop() {
                contexts.append(context)
            }
            handoffs[locationID] = handoff
        }
        contexts.forEach { $0.stop() }
        return teardowns
    }

    private func contextDidStop(_ context: ReceiverContext, locationID: Int) {
        guard var handoff = handoffs[locationID] else {
            return
        }
        let pending = handoff.didStop(context) { !$0.isRemoved }
        if handoff.isEmpty {
            handoffs.removeValue(forKey: locationID)
            if pending == nil {
                pendingRediscoveryRequests.removeValue(forKey: locationID)
            }
        } else {
            handoffs[locationID] = handoff
        }

        guard let pending else {
            return
        }
        startMonitoring(device: pending)
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
    private var slotsRequiringIdentityResolution = Set<UInt8>()

    mutating func reset() {
        pairedIdentitiesBySlot = [:]
        slotPresenceBySlot = [:]
        slotsRequiringIdentityResolution = []
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
        slotsRequiringIdentityResolution = []

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
            guard let kind = resolveReceiverLogicalDeviceKind(
                snapshotRaw: discovery.connectionSnapshots[slot]?.kind,
                pairingRaw: discovery.observedSlotKinds[slot]
            )
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
                slotsRequiringIdentityResolution.insert(slot)
            } else if !kind.isPointingDevice {
                pairedIdentitiesBySlot.removeValue(forKey: slot)
            }
        }

        let inventoryComplete = discovery.inventoryAvailable
            && discovery.expectedConnectedDeviceCount != nil
            && connectedSlots.count == discovery.expectedConnectedDeviceCount
            && slotKinds.count == connectedSlots.count
            && !hasUnresolvedConnectedSlot
        return .init(inventoryComplete: inventoryComplete)
    }

    mutating func mergeConnectionSnapshots(
        _ newSnapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot],
        reconnectedSlots: Set<UInt8> = []
    ) {
        for (slot, snapshot) in newSnapshots {
            let newPresence: SlotPresenceState = snapshot.isConnected ? .connected : .disconnected
            let oldPresence = slotPresenceBySlot[slot]
            slotPresenceBySlot[slot] = newPresence

            guard newPresence == .connected else {
                slotsRequiringIdentityResolution.remove(slot)
                continue
            }

            let pairingKind = pairedIdentitiesBySlot[slot]?.kind.rawValue
            let effectiveKind = resolveReceiverLogicalDeviceKind(
                snapshotRaw: snapshot.kind,
                pairingRaw: pairingKind
            )
            if snapshot.kind != nil, effectiveKind == nil {
                pairedIdentitiesBySlot.removeValue(forKey: slot)
                slotsRequiringIdentityResolution.insert(slot)
                continue
            }
            if let effectiveKind, !effectiveKind.isPointingDevice {
                // An explicitly non-pointing device cannot inherit a stale
                // mouse identity or hold up pointing-device discovery.
                pairedIdentitiesBySlot.removeValue(forKey: slot)
                slotsRequiringIdentityResolution.remove(slot)
                continue
            }

            // Clear stale identity when a device reconnects to a slot,
            // so the next needsIdentityRefresh check will trigger a refresh.
            if oldPresence == .disconnected || reconnectedSlots.contains(slot) {
                pairedIdentitiesBySlot.removeValue(forKey: slot)
            }

            if pairedIdentitiesBySlot[slot] == nil {
                slotsRequiringIdentityResolution.insert(slot)
            } else {
                slotsRequiringIdentityResolution.remove(slot)
            }
        }
    }

    mutating func updateSlotIdentity(_ identity: ReceiverLogicalDeviceIdentity) {
        pairedIdentitiesBySlot[identity.slot] = identity
        slotPresenceBySlot[identity.slot] = .connected
        slotsRequiringIdentityResolution.remove(identity.slot)
    }

    func needsIdentityRefresh(slot: UInt8) -> Bool {
        pairedIdentitiesBySlot[slot] == nil
    }

    /// A connected slot without an identity cannot be used as a stable route.
    /// Discovery must retry until its transient identity read succeeds.
    var hasUnresolvedConnectedSlot: Bool {
        slotsRequiringIdentityResolution.contains { slot in
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
    private var rediscoveryRequest: ReceiverRediscoveryRequest?
    private var lastCompleteConnectedDeviceCount: Int?
    private let retrySemaphore = DispatchSemaphore(value: 0)
    /// Receiver notification flags belong to this monitor context rather than
    /// one transient IOHID channel. Reopening the same physical receiver can
    /// therefore retry a restore that the retiring channel could not finish.
    private let notificationOwnershipRegistration: ReceiverNotificationOwnershipSessionRegistry.Registration
    var notificationOwnershipSession: ReceiverNotificationOwnershipSession {
        notificationOwnershipRegistration.session
    }

    var onDiscoveryTimedOut: (() -> Void)?
    var onSlotsChanged: ((ReceiverDiscoveryPublication) -> Void)?
    var onStopped: (() -> Void)?
    init(device: Device, locationID: Int, provider: LogitechHIDPPDeviceMetadataProvider) {
        self.device = device
        self.locationID = locationID
        self.provider = provider
        notificationOwnershipRegistration = LogitechReceiverChannel.registerNotificationOwnershipSession(
            locationID: locationID,
            proposed: ReceiverNotificationOwnershipSession()
        )
    }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isRunning else {
            return
        }
        isRunning = true
        rediscoveryRequest = nil
        lastCompleteConnectedDeviceCount = nil
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

    func requestRediscovery(_ request: ReceiverRediscoveryRequest) {
        stateLock.lock()
        guard isRunning else {
            stateLock.unlock()
            return
        }

        rediscoveryRequest = request
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
        var rediscoveryInProgress: ReceiverRediscoveryRequest?
        var discoveryBackoff = ExponentialBackoff(
            initialDelay: ReceiverMonitor.channelOpenRetryInterval,
            maximumDelay: ReceiverMonitor.maximumDiscoveryRetryInterval
        )
        defer {
            retireCurrentChannel()
            LogitechReceiverChannel.unregisterNotificationOwnershipSession(
                locationID: locationID,
                matching: notificationOwnershipRegistration
            )
            markStopped()
            DispatchQueue.main.async { [weak self] in
                self?.onStopped?()
            }
        }

        workerLoop: while shouldContinueRunning() {
            if let request = consumeRediscoveryRequest() {
                rediscoveryInProgress = request
                discoveryState = .pending
                discoveryBackoff.reset()
            }

            if currentChannelSnapshot() == nil {
                let channel = provider.openReceiverChannel(
                    for: device.pointerDevice,
                    notificationOwnershipSession: notificationOwnershipSession
                )
                if let channel {
                    guard adoptCurrentChannelIfRunning(channel) else {
                        _ = LogitechReceiverChannel.retireSharedChannel(
                            locationID: locationID,
                            matching: channel
                        )
                        break
                    }
                } else if !shouldContinueRunning() {
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
            ) == .lightspeed {
                guard let probe = ReceiverWorkerPostCallAdmission.admit(
                    {
                        provider.receiverChannelIsReachable(
                            for: device.pointerDevice,
                            using: receiverChannel,
                            until: shouldContinueRunning
                        )
                    },
                    whileRunning: shouldContinueRunning
                ) else {
                    break
                }
                if !probe.value {
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
            }

            // A receiver has no usable route until full discovery succeeds.
            if case .pending = discoveryState {
                guard let admitted = ReceiverWorkerPostCallAdmission.admit(
                    {
                        provider.receiverPointingDeviceDiscovery(
                            for: device.pointerDevice,
                            using: receiverChannel,
                            until: shouldContinueRunning
                        )
                    },
                    whileRunning: shouldContinueRunning
                ) else {
                    break
                }
                let discovery = admitted.value
                let mergeResult = mergeDiscovery(discovery)

                let identities = currentPublishedIdentities()
                if !mergeResult.inventoryComplete {
                    guard let reachability = ReceiverWorkerPostCallAdmission.admit(
                        {
                            provider.receiverChannelIsReachable(
                                for: device.pointerDevice,
                                using: receiverChannel,
                                until: shouldContinueRunning
                            )
                        },
                        whileRunning: shouldContinueRunning
                    ) else {
                        break
                    }
                    publishUnavailable()
                    if case .reopenChannel = ReceiverPendingDiscoveryDisposition.resolve(
                        inventoryAvailable: discovery.inventoryAvailable,
                        channelReachable: reachability.value
                    ) {
                        invalidateCurrentChannel(receiverChannel)
                        lastCompleteConnectedDeviceCount = nil
                    }
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

                // A request arriving during discovery cannot be acknowledged
                // by an inventory read that may have started before it. Run a
                // new discovery and publish only the request it actually
                // follows.
                if let newerRequest = consumeRediscoveryRequest() {
                    rediscoveryInProgress = newerRequest
                    discoveryState = .pending
                    discoveryBackoff.reset()
                    continue
                }

                discoveryState = .ready
                discoveryBackoff.reset()
                lastCompleteConnectedDeviceCount = discovery.expectedConnectedDeviceCount
                let completedRediscovery = rediscoveryInProgress
                rediscoveryInProgress = nil
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

                if identities != lastPublishedIdentities
                    || !hasPublishedInitialState
                    || completedRediscovery != nil {
                    publish(identities, rediscoveryRequest: completedRediscovery)
                    hasPublishedInitialState = true
                }
            }

            // Wait for connection events (event-driven, no periodic rescan)
            guard let admitted = ReceiverWorkerPostCallAdmission.admit(
                {
                    provider.waitForReceiverConnectionChange(
                        for: device.pointerDevice,
                        using: receiverChannel,
                        timeout: ReceiverMonitor.refreshInterval
                    ) { [weak self] in
                        self?.shouldContinueWaitingForNotifications() ?? false
                    }
                },
                whileRunning: shouldContinueRunning
            ) else {
                break
            }
            let connectionBatch = admitted.value

            if hasRediscoveryRequest() {
                continue
            }

            guard !connectionBatch.snapshots.isEmpty else {
                // Timeout with no events — verify channel is still alive
                guard let reachability = ReceiverWorkerPostCallAdmission.admit(
                    {
                        provider.receiverChannelIsReachable(
                            for: device.pointerDevice,
                            using: receiverChannel,
                            until: shouldContinueRunning
                        )
                    },
                    whileRunning: shouldContinueRunning
                ) else {
                    break
                }
                if !reachability.value {
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
                    lastCompleteConnectedDeviceCount = nil
                } else {
                    guard let count = ReceiverWorkerPostCallAdmission.admit(
                        {
                            provider.connectedDeviceCount(
                                for: device.pointerDevice,
                                using: receiverChannel,
                                until: shouldContinueRunning
                            )
                        },
                        whileRunning: shouldContinueRunning
                    ) else {
                        break
                    }
                    if case .enterPending = ReceiverReadyCountDisposition.resolve(
                        previousCount: lastCompleteConnectedDeviceCount,
                        currentCount: count.value
                    ) {
                        publishUnavailable()
                        discoveryState = .pending
                        discoveryBackoff.reset()
                        lastCompleteConnectedDeviceCount = nil
                    }
                }
                continue
            }

            if ReceiverReconnectPublication.requiresRouteLoss(
                reconnectedSlots: connectionBatch.reconnectedSlots,
                snapshots: connectionBatch.snapshots,
                currentIdentities: currentPublishedIdentities()
            ) {
                // Preserve a route-loss transition even when the refreshed
                // identity is available in this same notification batch.
                publishUnavailable()
            }

            mergeConnectionSnapshots(
                connectionBatch.snapshots,
                reconnectedSlots: connectionBatch.reconnectedSlots
            )

            // For newly connected devices, read their identity info
            for (slot, snapshot) in connectionBatch.snapshots where snapshot.isConnected {
                if needsIdentityRefresh(slot: slot) {
                    guard refreshSlotIdentity(
                        slot: slot,
                        connectionSnapshot: snapshot,
                        using: receiverChannel
                    ) else {
                        break workerLoop
                    }
                }
            }

            guard shouldContinueRunning() else {
                break
            }

            let snapshotDescription = connectionBatch.snapshots
                .keys
                .sorted()
                .compactMap { slot -> String? in
                    guard let snapshot = connectionBatch.snapshots[slot] else {
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
            let hasUnresolvedConnectedSlot = hasUnresolvedConnectedSlot()
            let identitiesToPublish = ReceiverConnectionEventPublication.identities(
                afterEvent: identities,
                hasUnresolvedConnectedSlot: hasUnresolvedConnectedSlot
            )
            if hasUnresolvedConnectedSlot {
                // A reconnect identity read can fail transiently. Re-enter the
                // existing pending-discovery path, which retries with backoff
                // instead of keeping this incomplete slot in the ready state.
                discoveryState = .pending
                discoveryBackoff.reset()
                publishUnavailable()
                continue
            }
            if identitiesToPublish != lastPublishedIdentities {
                publish(identitiesToPublish)
            }
        }
    }

    private func publish(
        _ identities: [ReceiverLogicalDeviceIdentity],
        rediscoveryRequest: ReceiverRediscoveryRequest? = nil
    ) {
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
            self?.onSlotsChanged?(.init(
                identities: identities,
                rediscoveryRequest: rediscoveryRequest
            ))
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
        return rediscoveryRequest != nil
    }

    private func shouldContinueWaitingForNotifications() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning && rediscoveryRequest == nil
    }

    private func consumeRediscoveryRequest() -> ReceiverRediscoveryRequest? {
        stateLock.lock()
        defer { stateLock.unlock() }

        let request = rediscoveryRequest
        rediscoveryRequest = nil
        return request
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

    private func adoptCurrentChannelIfRunning(_ channel: LogitechReceiverChannel) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return ReceiverWorkerChannelAdoption.adopt(
            channel,
            whileRunning: isRunning,
            currentChannel: &currentChannel
        )
    }

    private func invalidateCurrentChannel(_ channel: LogitechReceiverChannel) {
        stateLock.lock()
        guard isRunning, currentChannel === channel else {
            stateLock.unlock()
            return
        }
        currentChannel = nil
        stateLock.unlock()

        // The context gives up its local reference first. Shared retirement
        // then keeps the physical location closed while cancellation runs,
        // without blocking stop() on stateLock.
        _ = LogitechReceiverChannel.retireSharedChannel(
            locationID: locationID,
            matching: channel
        )
        stateStore.invalidateChannel()
        lastCompleteConnectedDeviceCount = nil
        publish([])
    }

    private func currentChannelSnapshot() -> LogitechReceiverChannel? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentChannel
    }

    private func retireCurrentChannel() {
        stateLock.lock()
        let channel = currentChannel
        currentChannel = nil
        stateLock.unlock()

        if let channel {
            _ = LogitechReceiverChannel.retireSharedChannel(
                locationID: locationID,
                matching: channel
            )
        }
    }

    private func mergeDiscovery(
        _ discovery: LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery
    ) -> ReceiverSlotStateStore.DiscoveryMergeResult {
        stateStore.mergeDiscovery(discovery)
    }

    private func mergeConnectionSnapshots(
        _ newSnapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot],
        reconnectedSlots: Set<UInt8> = []
    ) {
        guard !newSnapshots.isEmpty else {
            return
        }

        stateStore.mergeConnectionSnapshots(newSnapshots, reconnectedSlots: reconnectedSlots)
    }

    private func refreshSlotIdentity(
        slot: UInt8,
        connectionSnapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot?,
        using receiverChannel: LogitechReceiverChannel
    ) -> Bool {
        guard let admitted = ReceiverWorkerPostCallAdmission.admit(
            {
                provider.validateReceiverSlotIdentity(
                    for: device.pointerDevice,
                    slot: slot,
                    connectionSnapshot: connectionSnapshot,
                    using: receiverChannel,
                    deadline: Date().addingTimeInterval(ReceiverMonitor.identityRefreshTimeout),
                    until: shouldContinueRunning
                )
            },
            whileRunning: shouldContinueRunning
        ) else {
            return false
        }
        guard let identity = admitted.value else {
            return true
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
        return true
    }

    private func needsIdentityRefresh(slot: UInt8) -> Bool {
        stateStore.needsIdentityRefresh(slot: slot)
    }

    private func hasUnresolvedConnectedSlot() -> Bool {
        stateStore.hasUnresolvedConnectedSlot
    }

    private func currentPublishedIdentities() -> [ReceiverLogicalDeviceIdentity] {
        stateStore.currentPublishedIdentities()
    }
}
