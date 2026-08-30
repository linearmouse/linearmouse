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

/// Identifies the receiver whose notification register LinearMouse changed.
/// A serial-backed target can survive channel reconstruction. A session target
/// is deliberately meaningful only to the channel that created it, so an
/// unidentified replacement receiver cannot inherit its teardown writes.
enum ReceiverNotificationOwnershipTarget: Hashable {
    case receiver(vendorID: Int, serialNumber: String)
    case session(ReceiverNotificationSessionIdentity)

    static func receiver(vendorID: Int?, serialNumber: String?) -> Self? {
        guard let vendorID,
              let serialNumber
        else {
            return nil
        }

        let normalizedSerial = serialNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedSerial.isEmpty else {
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

    /// Enables `requestedBits` with read-modify-write. Bits already set belong
    /// to someone else and are not captured. Failed writes acquire no ownership.
    @discardableResult
    func enable(
        _ requestedBits: UInt32,
        for target: ReceiverNotificationOwnershipTarget,
        read: () -> UInt32?,
        write: (UInt32) -> Bool,
        shouldContinue: () -> Bool = { true }
    ) -> Bool {
        mutationLock.lock()
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
        guard shouldContinue(), write(current | requestedBits) else {
            return false
        }

        // The write happened even if ownership changed immediately afterwards;
        // retaining the claim lets a reconstructed channel for the same stable
        // receiver finish the restore.
        capture(addedBits, for: target)
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
        mutationLock.lock()
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
            guard shouldContinue(),
                  write(restored),
                  shouldContinue(),
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
    func enableWirelessNotifications()
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
    func discoverBoltSlots() -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotDiscovery? {
        // Enable connection notifications before requesting the initial snapshot.
        // Ongoing monitoring revalidates the flags before each passive wait.
        enableWirelessNotifications()

        guard readBoltUniqueID() != nil else {
            os_log(
                "Bolt receiver unique ID is unavailable: locationID=%{public}@",
                log: LogitechHIDPPDeviceMetadataProvider.log,
                type: .info,
                locationID.map(String.init) ?? "(nil)"
            )
            return nil
        }

        let connectedDeviceCount = readBoltConnectionState().flatMap {
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount($0.bytes)
        }
        let connectionSnapshots = discoverBoltConnectionSnapshots(expectedCount: connectedDeviceCount)
        let pairedSlots = (UInt8(1) ... UInt8(6)).compactMap {
            discoverBoltSlotInfo($0, connectionSnapshot: connectionSnapshots[$0])
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
        connectionSnapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo? {
        let metadataProvider = LogitechHIDPPDeviceMetadataProvider()
        let pairingResponse = boltReceiverInfoRequest(subregister: UInt8(0x50 + Int(slot)))
        let nameResponse = boltReceiverInfoRequest(subregister: UInt8(0x60 + Int(slot)), parameters: [0x01])

        guard pairingResponse != nil || nameResponse != nil else {
            return nil
        }

        let routedTransport = HIDPPTransport(device: self, deviceIndex: slot)
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

    func discoverBoltPointingDeviceDiscovery(
        baseName: String
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery {
        guard let locationID,
              let discovery = discoverBoltSlots()
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

    private func readBoltUniqueID() -> BoltHIDPP10Report? {
        boltHIDPP10LongRequest(register: 0xFB, parameters: [])
    }

    private func readBoltConnectionState() -> BoltHIDPP10Report? {
        boltHIDPP10ShortRequest(
            subID: 0x81,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0, 0, 0]
        )
    }

    func boltConnectedDeviceCount() -> Int? {
        readBoltConnectionState().flatMap {
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount($0.bytes)
        }
    }

    private func triggerBoltConnectionNotifications() -> Bool {
        boltHIDPP10ShortRequest(
            subID: 0x80,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0x02, 0x00, 0x00]
        ) != nil
    }

    private func discoverBoltConnectionSnapshots(
        expectedCount: Int? = nil
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        guard triggerBoltConnectionNotifications() else {
            return [:]
        }

        return collectBoltConnectionSnapshots(timeout: 0.5, expectedCount: expectedCount, until: nil)
    }

    func waitForBoltConnectionSnapshots(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotBatch {
        // Retrying this idempotent setup recovers from a transient failure without
        // triggering a connection snapshot or short-circuiting the bounded wait.
        enableWirelessNotifications()

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

    func isBoltReceiverReachable() -> Bool {
        readBoltUniqueID() != nil
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
        parameters: [UInt8] = []
    ) -> BoltHIDPP10Report? {
        boltHIDPP10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            parameters: [subregister] + parameters,
            firstParameter: subregister
        )
    }

    private func boltHIDPP10ShortRequest(
        subID: UInt8,
        register: UInt8,
        parameters: [UInt8]
    ) -> BoltHIDPP10Report? {
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = subID
        bytes[3] = register
        for (index, parameter) in parameters.prefix(3).enumerated() {
            bytes[4 + index] = parameter
        }

        let response = performSynchronousOutputReportRequest(
            Data(bytes),
            timeout: LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        ) { report in
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

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : .init(bytes: responseBytes)
    }

    private func boltHIDPP10LongRequest(
        register: UInt8,
        parameters: [UInt8],
        firstParameter: UInt8? = nil
    ) -> BoltHIDPP10Report? {
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = 0x83
        bytes[3] = register
        for (index, parameter) in parameters.prefix(3).enumerated() {
            bytes[4 + index] = parameter
        }

        let response = performSynchronousOutputReportRequest(
            Data(bytes),
            timeout: LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        ) { report in
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

        return response[8 ... 11].map { String(format: "%02X", $0) }.joined()
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
