// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import os.log

/// HID++ 1.0 report used by Bolt receiver discovery and connection monitoring.
private struct BoltHIDPP10Report {
    let bytes: [UInt8]
}

/// Concrete ownership identity for a receiver channel that lacks a stable
/// hardware serial. It is intentionally never recreated from metadata.
final class ReceiverNotificationSessionIdentity: Hashable {
    static func == (lhs: ReceiverNotificationSessionIdentity, rhs: ReceiverNotificationSessionIdentity) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// Owns notification-register mutations for one concrete receiver-monitor
/// context. It may span safe channel reconstruction, but an unidentified
/// replacement context must never inherit the old ownership.
final class ReceiverNotificationOwnershipSession {
    let identity = ReceiverNotificationSessionIdentity()
    let store = ReceiverNotificationOwnershipStore()
}

/// Weakly associates one live receiver-monitor context with its notification
/// ownership session. The registry is used only while the caller holds the
/// receiver channel registry lock; it does not create another lifetime owner.
final class ReceiverNotificationOwnershipSessionRegistry {
    final class Registration {
        let session: ReceiverNotificationOwnershipSession

        init(session: ReceiverNotificationOwnershipSession) {
            self.session = session
        }
    }

    struct OpenResolution {
        let session: ReceiverNotificationOwnershipSession
        fileprivate let registration: Registration
    }

    private final class WeakRegistration {
        weak var value: Registration?

        init(_ value: Registration) {
            self.value = value
        }
    }

    private var registrationsByLocation = [Int: WeakRegistration]()

    /// Registers a context. If a channel already exists, its concrete session
    /// becomes the context session so adoption never splits ownership.
    func register(
        locationID: Int,
        proposed: ReceiverNotificationOwnershipSession,
        existingChannelSession: ReceiverNotificationOwnershipSession?
    ) -> Registration {
        if let existingChannelSession {
            if let current = registrationsByLocation[locationID]?.value,
               current.session === existingChannelSession {
                return current
            }
            let registration = Registration(session: existingChannelSession)
            registrationsByLocation[locationID] = WeakRegistration(registration)
            return registration
        }
        if let current = registrationsByLocation[locationID]?.value {
            return current
        }

        let registration = Registration(session: proposed)
        registrationsByLocation[locationID] = WeakRegistration(registration)
        return registration
    }

    /// Every channel creator resolves the registered context session, including
    /// callers that do not themselves know about ReceiverContext.
    func resolveForOpen(
        locationID: Int,
        proposed: ReceiverNotificationOwnershipSession
    ) -> OpenResolution {
        if let registration = registrationsByLocation[locationID]?.value {
            return OpenResolution(
                session: registration.session,
                registration: registration
            )
        }

        let registration = Registration(session: proposed)
        registrationsByLocation[locationID] = WeakRegistration(registration)
        return OpenResolution(
            session: proposed,
            registration: registration
        )
    }

    /// A channel prepared before context registration must not publish with the
    /// now-wrong session. It is closed and the context's next retry opens one
    /// with the registered session instead.
    func permitsAdoption(
        locationID: Int,
        resolution: OpenResolution
    ) -> Bool {
        guard let current = registrationsByLocation[locationID]?.value else {
            return false
        }
        return current === resolution.registration
            && current.session === resolution.session
    }

    func unregister(
        locationID: Int,
        registration: Registration
    ) {
        guard registrationsByLocation[locationID]?.value === registration else {
            return
        }
        registrationsByLocation.removeValue(forKey: locationID)
    }
}

/// Concrete identities for the three mutually exclusive receiver lifecycle
/// operations. The objects themselves are the identity; none can be recreated
/// from a counter, timestamp, or device metadata.
final class ReceiverChannelOpeningOwnership {}
final class ReceiverChannelClosingOwnership {}
final class ReceiverChannelTerminalOwnership {}

/// A short best-effort budget for ordinary channel retirement. Sleep can
/// suspend a receiver before its worker unwinds; teardown must not let a full
/// HID++ timeout delay the replacement channel after wake.
struct ReceiverChannelRetirementBudget {
    static let timeout: TimeInterval = 0.25

    let deadline: Date

    init(now: Date = Date(), timeout: TimeInterval = Self.timeout) {
        deadline = now.addingTimeInterval(timeout)
    }

    func shouldContinue(
        now: Date = Date(),
        transportIsActive: Bool
    ) -> Bool {
        transportIsActive && now < deadline
    }
}

/// A small exact-owner primitive shared by opening, closing, and terminal
/// admission. Slow IOKit work always happens outside the lock that protects
/// these registries.
struct ReceiverChannelOwnershipRegistry<Ownership: AnyObject> {
    private var ownershipByLocation = [Int: Ownership]()

    mutating func begin(
        locationID: Int,
        ownership: Ownership
    ) -> Bool {
        guard ownershipByLocation[locationID] == nil else {
            return false
        }
        ownershipByLocation[locationID] = ownership
        return true
    }

    func isClaimed(locationID: Int) -> Bool {
        ownershipByLocation[locationID] != nil
    }

    func isOwned(
        locationID: Int,
        by ownership: Ownership
    ) -> Bool {
        ownershipByLocation[locationID] === ownership
    }

    @discardableResult
    mutating func release(
        locationID: Int,
        ownership: Ownership
    ) -> Bool {
        guard ownershipByLocation[locationID] === ownership else {
            return false
        }
        ownershipByLocation.removeValue(forKey: locationID)
        return true
    }
}

/// Closes the receiver-monitor mutation side of a channel before terminal
/// restoration starts. Existing HID++ transactions may finish, but a producer
/// that has not committed its notification-register write must observe the
/// closed admission on its second continuation check.
final class ReceiverChannelTerminalAdmission {
    private let lock = NSLock()
    private var ownership: ReceiverChannelTerminalOwnership?

    var allowsProducerMutation: Bool {
        lock.withLock { ownership == nil }
    }

    @discardableResult
    func begin(ownership: ReceiverChannelTerminalOwnership) -> Bool {
        lock.withLock {
            guard self.ownership == nil else {
                return false
            }
            self.ownership = ownership
            return true
        }
    }

    func isOwned(by expected: ReceiverChannelTerminalOwnership) -> Bool {
        lock.withLock { ownership === expected }
    }
}

/// Joins duplicate terminal-finish callers onto one physical channel close.
/// Every registered completion is delivered once, while only the first caller
/// receives ownership of the close operation.
final class ReceiverChannelTerminalFinishState {
    typealias Delivery = (@escaping () -> Void) -> Void

    private enum Phase {
        case active
        case finishing
        case finished
    }

    private let lock = NSLock()
    private let delivery: Delivery
    private var phase = Phase.active
    private var completions = [() -> Void]()

    init(delivery: @escaping Delivery) {
        self.delivery = delivery
    }

    var allowsRestore: Bool {
        lock.withLock {
            if case .active = phase {
                return true
            }
            return false
        }
    }

    /// Returns true only to the caller that must detach and close the channel.
    @discardableResult
    func begin(completion: @escaping () -> Void) -> Bool {
        let result = lock.withLock { () -> (startsClose: Bool, deliversNow: Bool) in
            switch phase {
            case .active:
                phase = .finishing
                completions.append(completion)
                return (true, false)
            case .finishing:
                completions.append(completion)
                return (false, false)
            case .finished:
                return (false, true)
            }
        }

        if result.deliversNow {
            delivery(completion)
        }
        return result.startsClose
    }

    func complete() {
        let completions = lock.withLock { () -> [() -> Void] in
            guard case .finishing = phase else {
                return []
            }
            phase = .finished
            defer { self.completions.removeAll() }
            return self.completions
        }
        guard !completions.isEmpty else {
            return
        }
        delivery {
            completions.forEach { $0() }
        }
    }
}

/// Atomically hands one late-opened resource to a terminal request or rejects
/// it after finishing has begun. This closes the otherwise tiny window between
/// publishing a channel and retaining it for teardown.
final class ReceiverChannelTerminalResource<Resource: AnyObject> {
    private let lock = NSLock()
    private var acceptsResource = true
    private var resource: Resource?

    init(_ resource: Resource?) {
        self.resource = resource
    }

    var current: Resource? {
        lock.withLock { resource }
    }

    func accept(_ resource: Resource) -> Bool {
        lock.withLock {
            guard acceptsResource, self.resource == nil else {
                return false
            }
            self.resource = resource
            return true
        }
    }

    func takeForFinish() -> Resource? {
        lock.withLock {
            acceptsResource = false
            defer { resource = nil }
            return resource
        }
    }
}

/// Identifies the receiver whose notification register LinearMouse changed.
/// A serial-backed target can survive channel reconstruction. A session target
/// is deliberately meaningful only to the concrete channel that created it,
/// so an unidentified replacement receiver cannot inherit it.
enum ReceiverNotificationOwnershipTarget: Hashable {
    case receiver(vendorID: Int, serialNumber: String)
    case session(ReceiverNotificationSessionIdentity)

    static func stableReceiver(vendorID: Int?, serialNumber: String?) -> Self? {
        guard let vendorID,
              let normalizedSerial = LogitechStableSerial.normalize(serialNumber)
        else {
            return nil
        }

        return .receiver(vendorID: vendorID, serialNumber: normalizedSerial)
    }
}

/// Owns only the receiver notification bits that this process actually added.
/// The process-wide instance is used only for serial-backed receivers; an
/// unidentified receiver uses a channel-local instance of the same primitive.
final class ReceiverNotificationOwnershipStore {
    fileprivate final class EntryOwnership {}

    struct Handle: Hashable {
        fileprivate let target: ReceiverNotificationOwnershipTarget
        fileprivate let ownership: EntryOwnership
        fileprivate let ownedBits: UInt32

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.target == rhs.target
                && lhs.ownership === rhs.ownership
                && lhs.ownedBits == rhs.ownedBits
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(target)
            hasher.combine(ObjectIdentifier(ownership))
            hasher.combine(ownedBits)
        }

        func belongs(to target: ReceiverNotificationOwnershipTarget) -> Bool {
            self.target == target
        }

        func ownsSameEntry(as other: Self) -> Bool {
            target == other.target && ownership === other.ownership
        }
    }

    struct Claim: Equatable {
        let ownedBits: UInt32
        let handle: Handle
    }

    private struct Entry {
        var ownedBits: UInt32
        let ownership = EntryOwnership()
    }

    private let mutationLock = NSLock()
    private let lock = NSLock()
    private var entries = [ReceiverNotificationOwnershipTarget: Entry]()

    /// Convenience for transports where a successful return is also the exact
    /// report-commit boundary.
    @discardableResult
    func enable(
        _ requestedBits: UInt32,
        for target: ReceiverNotificationOwnershipTarget,
        read: () -> UInt32?,
        write: (UInt32) -> Bool,
        shouldContinue: () -> Bool = { true }
    ) -> Bool {
        enable(
            requestedBits,
            for: target,
            read: read,
            committingWrite: { value, didCommit in
                let acknowledged = write(value)
                if acknowledged {
                    didCommit()
                }
                return acknowledged
            },
            shouldContinue: shouldContinue
        )
    }

    /// Enables `requestedBits` with read-modify-write. Bits already set belong
    /// to someone else and are not captured. Ownership is recorded at the
    /// transport's successful SetReport boundary, before waiting for an ACK;
    /// terminal admission can therefore close immediately after a committed
    /// write without making that mutation un-restorable.
    @discardableResult
    func enable(
        _ requestedBits: UInt32,
        for target: ReceiverNotificationOwnershipTarget,
        read: () -> UInt32?,
        committingWrite: (_ value: UInt32, _ didCommit: () -> Void) -> Bool,
        shouldContinue: () -> Bool = { true }
    ) -> Bool {
        guard acquireMutationLock(while: shouldContinue) else {
            return false
        }
        defer { mutationLock.unlock() }

        guard shouldContinue(),
              let current = read()
        else {
            return false
        }

        let addedBits = requestedBits & ~current
        guard addedBits != 0 else {
            return true
        }
        var committed = false
        let acknowledged = shouldContinue() && committingWrite(current | requestedBits) {
            guard !committed else {
                return
            }
            committed = true
            self.capture(addedBits, for: target)
        }
        if !acknowledged {
            if committed {
                return false
            }
            // A receiver can commit the register write even when its reply is
            // lost. Confirm only the bits that were absent in the pre-write
            // snapshot; pre-existing bits still belong to somebody else.
            guard shouldContinue(),
                  let readback = read(),
                  readback & addedBits == addedBits
            else {
                return false
            }
        }

        // Test and compatibility transports may only identify commitment by a
        // positive ACK/readback. Production HID I/O calls didCommit earlier.
        if !committed {
            capture(addedBits, for: target)
        }
        return true
    }

    /// Clears a snapshot of the bits owned for `target`, using the latest
    /// register value as the base so every unrelated bit observed there survives.
    /// A successful write is read back before ownership is consumed.
    @discardableResult
    func restoreOwnedBits(
        for target: ReceiverNotificationOwnershipTarget,
        read: () -> UInt32?,
        write: (UInt32) -> Bool,
        shouldContinue: () -> Bool = { true }
    ) -> Bool {
        guard acquireMutationLock(while: shouldContinue) else {
            return false
        }
        defer { mutationLock.unlock() }

        guard let claim = claim(for: target) else {
            return true
        }
        guard shouldContinue(),
              let current = read()
        else {
            return false
        }

        let restored = current & ~claim.ownedBits
        if restored != current {
            guard shouldContinue() else {
                return false
            }
            // The ACK is advisory: the receiver may commit the register write
            // and lose only its reply. Readback is the restoration authority.
            _ = write(restored)
            guard shouldContinue(),
                  let readback = read(),
                  readback & claim.ownedBits == 0
            else {
                return false
            }
        }

        guard shouldContinue() else {
            return false
        }
        return consumeRestoredBits(claim.handle)
    }

    private func acquireMutationLock(while shouldContinue: () -> Bool) -> Bool {
        while shouldContinue() {
            if mutationLock.lock(before: Date().addingTimeInterval(0.01)) {
                return true
            }
        }
        return false
    }

    func claim(for target: ReceiverNotificationOwnershipTarget) -> Claim? {
        lock.withLock {
            guard let entry = entries[target] else {
                return nil
            }

            return Claim(
                ownedBits: entry.ownedBits,
                handle: Handle(
                    target: target,
                    ownership: entry.ownership,
                    ownedBits: entry.ownedBits
                )
            )
        }
    }

    /// Removes only the bits represented by this exact ownership snapshot.
    /// Bits added to the same entry after the snapshot remain pending.
    @discardableResult
    func consumeRestoredBits(_ handle: Handle) -> Bool {
        lock.withLock {
            guard var entry = entries[handle.target],
                  entry.ownership === handle.ownership
            else {
                return false
            }

            entry.ownedBits &= ~handle.ownedBits
            if entry.ownedBits == 0 {
                entries.removeValue(forKey: handle.target)
            } else {
                entries[handle.target] = entry
            }
            return true
        }
    }

    private func capture(_ addedBits: UInt32, for target: ReceiverNotificationOwnershipTarget) {
        guard addedBits != 0 else {
            return
        }

        lock.withLock {
            if var entry = entries[target] {
                entry.ownedBits |= addedBits
                entries[target] = entry
            } else {
                entries[target] = Entry(ownedBits: addedBits)
            }
        }
    }
}

protocol LogitechReceiverMonitoringChannel: VendorSpecificDeviceContext {
    func enableWirelessNotifications(until shouldContinue: @escaping () -> Bool)
    func waitForReceiverConnectionNotification(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)?
    ) -> (slot: UInt8, snapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot)?
}

extension LogitechReceiverChannel: LogitechReceiverMonitoringChannel {
    func waitForReceiverConnectionNotification(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)?
    ) -> (slot: UInt8, snapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot)? {
        guard let report = waitForHIDPPNotification(
            timeout: timeout,
            matching: { response in
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(response) != nil
            },
            until: shouldContinue
        ) else {
            return nil
        }

        return LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(report)
    }
}

extension LogitechReceiverMonitoringChannel {
    func discoverBoltSlots(
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotDiscovery? {
        // Enable connection notifications before requesting the initial snapshot.
        // Ongoing monitoring revalidates the flags before each passive wait.
        enableWirelessNotifications(until: shouldContinue)

        guard shouldContinue(), readBoltUniqueID(
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        ) != nil else {
            os_log(
                "Bolt receiver unique ID is unavailable: locationID=%{public}@",
                log: LogitechHIDPPDeviceMetadataProvider.log,
                type: .info,
                locationID.map(String.init) ?? "(nil)"
            )
            return nil
        }

        let connectedDeviceCount = readBoltConnectionState(
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        ).flatMap {
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount($0.bytes)
        }
        guard shouldContinue() else {
            return nil
        }
        let connectionSnapshots = discoverBoltConnectionSnapshots(
            expectedCount: connectedDeviceCount,
            until: shouldContinue
        )
        var pairedSlots = [LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo]()
        for slot in UInt8(1) ... UInt8(6) {
            guard shouldContinue() else {
                return nil
            }
            if let slotInfo = discoverBoltSlotInfo(
                slot,
                connectionSnapshot: connectionSnapshots[slot],
                until: shouldContinue
            ) {
                pairedSlots.append(slotInfo)
            }
        }

        let inventoryAvailable = connectedDeviceCount != nil || !connectionSnapshots.isEmpty || !pairedSlots.isEmpty
        return .init(
            slots: pairedSlots,
            connectionSnapshots: connectionSnapshots,
            expectedConnectedDeviceCount: connectedDeviceCount,
            inventoryAvailable: inventoryAvailable
        )
    }

    func discoverBoltSlotInfo(
        _ slot: UInt8,
        connectionSnapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo? {
        let metadataProvider = LogitechHIDPPDeviceMetadataProvider()
        let deadline = Date().addingTimeInterval(
            LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
        )
        let pairingResponse = boltReceiverInfoRequest(
            subregister: UInt8(0x50 + Int(slot)),
            deadline: deadline,
            until: shouldContinue
        )
        let nameResponse = boltReceiverInfoRequest(
            subregister: UInt8(0x60 + Int(slot)),
            parameters: [0x01],
            deadline: deadline,
            until: shouldContinue
        )

        guard pairingResponse != nil || nameResponse != nil else {
            return nil
        }

        let routedTransport = HIDPPTransport(
            device: self,
            deviceIndex: slot,
            requestTimeout: LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout,
            shouldContinue: shouldContinue
        )
        let routedName = routedTransport.flatMap { transport in
            metadataProvider.readFriendlyName(using: transport) ?? metadataProvider.readName(using: transport)
        }
        let batteryLevel = routedTransport.flatMap {
            metadataProvider.readReceiverBatteryLevel(using: $0)
        }
        let kind = pairingResponse.flatMap { Self.parseBoltReceiverKind($0.bytes) }
            ?? connectionSnapshot?.kind
            ?? 0
        let name = routedName ?? nameResponse.flatMap { Self.parseBoltReceiverName($0.bytes) }

        return .init(
            slot: slot,
            kind: kind,
            name: name,
            productID: pairingResponse.flatMap { Self.parseBoltReceiverProductID($0.bytes) },
            serialNumber: pairingResponse.flatMap { Self.parseBoltReceiverSerialNumber($0.bytes) },
            batteryLevel: batteryLevel,
            hasLiveMetadata: routedName != nil || batteryLevel != nil
        )
    }

    func validateBoltSlotIdentity(
        _ slot: UInt8,
        deadline: Date,
        until shouldContinue: @escaping () -> Bool
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo? {
        guard let pairingResponse = boltReceiverInfoRequest(
            subregister: UInt8(0x50 + Int(slot)),
            deadline: deadline,
            until: shouldContinue
        ), shouldContinue() else {
            return nil
        }

        return .init(
            slot: slot,
            kind: Self.parseBoltReceiverKind(pairingResponse.bytes) ?? 0,
            name: nil,
            productID: Self.parseBoltReceiverProductID(pairingResponse.bytes),
            serialNumber: Self.parseBoltReceiverSerialNumber(pairingResponse.bytes),
            batteryLevel: nil,
            hasLiveMetadata: false
        )
    }

    func discoverBoltPointingDeviceDiscovery(
        baseName: String,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery {
        guard let locationID,
              let discovery = discoverBoltSlots(until: shouldContinue)
        else {
            return .init(
                identities: [],
                connectionSnapshots: [:],
                liveReachableSlots: [],
                inventoryAvailable: false
            )
        }

        let liveReachableSlots = Set(discovery.slots.compactMap { slot in
            slot.hasLiveMetadata ? slot.slot : nil
        })

        let identities = discovery.slots.compactMap { slot -> ReceiverLogicalDeviceIdentity? in
            guard let kind = resolveReceiverPointingIdentityKind(
                snapshotRaw: discovery.connectionSnapshots[slot.slot]?.kind,
                pairingRaw: slot.kind
            ), kind.isPointingDevice else {
                return nil
            }

            return ReceiverLogicalDeviceIdentity(
                receiverLocationID: locationID,
                slot: slot.slot,
                kind: kind,
                name: slot.name ?? baseName,
                serialNumber: slot.serialNumber,
                productID: slot.productID,
                batteryLevel: slot.batteryLevel
            )
        }

        return .init(
            identities: identities,
            connectionSnapshots: discovery.connectionSnapshots,
            liveReachableSlots: liveReachableSlots,
            expectedConnectedDeviceCount: discovery.expectedConnectedDeviceCount,
            inventoryAvailable: discovery.inventoryAvailable,
            observedSlotKinds: Dictionary(uniqueKeysWithValues: discovery.slots.map {
                ($0.slot, $0.kind)
            })
        )
    }

    private func readBoltUniqueID(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> BoltHIDPP10Report? {
        boltHIDPP10LongRequest(
            register: 0xFB,
            parameters: [],
            deadline: deadline,
            until: shouldContinue
        )
    }

    private func readBoltConnectionState(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> BoltHIDPP10Report? {
        boltHIDPP10ShortRequest(
            subID: 0x81,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0, 0, 0],
            deadline: deadline,
            until: shouldContinue
        )
    }

    func boltConnectedDeviceCount(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Int? {
        readBoltConnectionState(deadline: deadline, until: shouldContinue).flatMap {
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount($0.bytes)
        }
    }

    private func triggerBoltConnectionNotifications(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Bool {
        boltHIDPP10ShortRequest(
            subID: 0x80,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0x02, 0x00, 0x00],
            deadline: deadline,
            until: shouldContinue
        ) != nil
    }

    private func discoverBoltConnectionSnapshots(
        expectedCount: Int? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        guard triggerBoltConnectionNotifications(
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        ) else {
            return [:]
        }

        return collectBoltConnectionSnapshots(
            timeout: 0.5,
            expectedCount: expectedCount,
            until: shouldContinue
        )
    }

    func waitForBoltConnectionSnapshots(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotBatch {
        // Retrying this idempotent setup recovers from a transient failure without
        // triggering a connection snapshot or short-circuiting the bounded wait.
        enableWirelessNotifications(until: shouldContinue ?? { true })

        guard let initialNotification = waitForReceiverConnectionNotification(
            timeout: timeout,
            until: shouldContinue
        ) else {
            return .empty
        }

        var collector = LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotCollector(
            expectedConnectedDeviceCount: nil
        )
        collector.record(slot: initialNotification.slot, snapshot: initialNotification.snapshot)
        let deadline = Date().addingTimeInterval(0.1)
        while Date() < deadline, shouldContinue?() ?? true {
            guard let notification = waitForReceiverConnectionNotification(timeout: 0.02, until: shouldContinue) else {
                continue
            }

            collector.record(slot: notification.slot, snapshot: notification.snapshot)
        }

        return collector.batch
    }

    func isBoltReceiverReachable(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Bool {
        readBoltUniqueID(deadline: deadline, until: shouldContinue) != nil
    }

    private func collectBoltConnectionSnapshots(
        timeout: TimeInterval,
        expectedCount: Int? = nil,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        var collector = LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotCollector(
            expectedConnectedDeviceCount: expectedCount
        )
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, shouldContinue?() ?? true {
            guard let notification = waitForReceiverConnectionNotification(
                timeout: 0.05,
                until: shouldContinue
            ) else {
                if collector.isCompleteAfterQuietWait {
                    break
                }
                continue
            }

            collector.record(slot: notification.slot, snapshot: notification.snapshot)
        }

        return collector.snapshots
    }

    private func boltReceiverInfoRequest(
        subregister: UInt8,
        parameters: [UInt8] = [],
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> BoltHIDPP10Report? {
        boltHIDPP10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            parameters: [subregister] + parameters,
            firstParameter: subregister,
            deadline: deadline,
            until: shouldContinue
        )
    }

    private func boltHIDPP10ShortRequest(
        subID: UInt8,
        register: UInt8,
        parameters: [UInt8],
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> BoltHIDPP10Report? {
        let requestShouldContinue = {
            shouldContinue() && deadline.map { Date() < $0 } != false
        }
        let timeout = min(
            LogitechHIDPPDeviceMetadataProvider.Constants.timeout,
            deadline.map { max(0, $0.timeIntervalSinceNow) }
                ?? LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        )
        guard timeout > 0, requestShouldContinue() else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = subID
        bytes[3] = register
        for (index, parameter) in parameters.prefix(3).enumerated() {
            bytes[4 + index] = parameter
        }

        let matching: (Data) -> Bool = { report in
            let reply = [UInt8](report)
            guard reply.count >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength,
                  [
                      LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                      LogitechHIDPPDeviceMetadataProvider.Constants.longReportID
                  ].contains(reply[0]),
                  reply[1] == LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
            else {
                return false
            }

            if reply[2] == 0x8F {
                return reply[3] == subID && reply[4] == register
            }

            return reply[2] == subID && reply[3] == register
        }
        let response: Data?
        if let cancellable = self as? HIDPPCancellableDeviceIO {
            response = cancellable.performSynchronousOutputReportRequest(
                Data(bytes),
                timeout: timeout,
                matching: matching,
                until: requestShouldContinue
            )
        } else {
            guard requestShouldContinue() else {
                return nil
            }
            response = performSynchronousOutputReportRequest(
                Data(bytes),
                timeout: timeout,
                matching: matching
            )
        }

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : .init(bytes: responseBytes)
    }

    private func boltHIDPP10LongRequest(
        register: UInt8,
        parameters: [UInt8],
        firstParameter: UInt8? = nil,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> BoltHIDPP10Report? {
        let requestShouldContinue = {
            shouldContinue() && deadline.map { Date() < $0 } != false
        }
        let timeout = min(
            LogitechHIDPPDeviceMetadataProvider.Constants.timeout,
            deadline.map { max(0, $0.timeIntervalSinceNow) }
                ?? LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        )
        guard timeout > 0, requestShouldContinue() else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = 0x83
        bytes[3] = register
        for (index, parameter) in parameters.prefix(3).enumerated() {
            bytes[4 + index] = parameter
        }

        let matching: (Data) -> Bool = { report in
            let reply = [UInt8](report)
            guard reply.count >= 5,
                  [
                      LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                      LogitechHIDPPDeviceMetadataProvider.Constants.longReportID
                  ].contains(reply[0]),
                  reply[1] == LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
            else {
                return false
            }

            if reply[2] == 0x8F {
                return reply[3] == 0x83 && reply[4] == register
            }

            guard reply[2] == 0x83,
                  reply[3] == register
            else {
                return false
            }

            if let firstParameter {
                return reply.count > 4 && reply[4] == firstParameter
            }

            return true
        }
        let response: Data?
        if let cancellable = self as? HIDPPCancellableDeviceIO {
            response = cancellable.performSynchronousOutputReportRequest(
                Data(bytes),
                timeout: timeout,
                matching: matching,
                until: requestShouldContinue
            )
        } else {
            guard requestShouldContinue() else {
                return nil
            }
            response = performSynchronousOutputReportRequest(
                Data(bytes),
                timeout: timeout,
                matching: matching
            )
        }

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : .init(bytes: responseBytes)
    }

    static func parseBoltReceiverKind(_ response: [UInt8]) -> UInt8? {
        guard response.count >= 6 else {
            return nil
        }

        return response[5] & 0x0F
    }

    static func parseBoltReceiverProductID(_ response: [UInt8]) -> Int? {
        guard response.count >= 8 else {
            return nil
        }

        return Int(response[7]) << 8 | Int(response[6])
    }

    static func parseBoltReceiverSerialNumber(_ response: [UInt8]) -> String? {
        guard response.count >= 12 else {
            return nil
        }

        return LogitechStableSerial.encode(response[8 ... 11])
    }

    static func parseBoltReceiverName(_ response: [UInt8]) -> String? {
        guard response.count >= 7 else {
            return nil
        }

        let length = Int(response[6])
        let bytes = Array(response.dropFirst(7).prefix(length))
        guard !bytes.isEmpty else {
            return nil
        }

        return String(bytes: bytes, encoding: .utf8)
    }
}
