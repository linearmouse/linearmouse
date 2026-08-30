// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// A process-lifetime identity for hardware state that must survive a
/// PointerDevice/session rebuild (notably across system sleep).
enum LogitechHardwareTargetKey: Hashable {
    struct LegacyReceiverDescriptor: Hashable {
        let vendorID: Int
        let receiverLocationID: Int
        let kind: ReceiverLogicalDeviceKind
        let productID: Int
        let name: String
    }

    case serial(vendorID: Int, productID: Int, serial: String)
    case receiver(
        vendorID: Int,
        receiverLocationID: Int,
        slot: UInt8,
        kind: ReceiverLogicalDeviceKind,
        productID: Int,
        name: String
    )
    case direct(
        transport: String,
        locationID: Int,
        vendorID: Int,
        productID: Int,
        name: String
    )

    static func direct(
        transport: String?,
        locationID: Int?,
        vendorID: Int?,
        productID: Int?,
        serialNumber: String?,
        name: String?
    ) -> Self? {
        guard let vendorID, let productID else {
            return nil
        }
        if let serial = normalized(serialNumber) {
            return .serial(vendorID: vendorID, productID: productID, serial: serial)
        }
        guard let transport,
              let locationID,
              let name = normalized(name) else {
            return nil
        }
        return .direct(
            transport: transport,
            locationID: locationID,
            vendorID: vendorID,
            productID: productID,
            name: name
        )
    }

    static func receiver(
        vendorID: Int?,
        receiverLocationID: Int?,
        identity: ReceiverLogicalDeviceIdentity
    ) -> Self? {
        guard let vendorID,
              let receiverLocationID else {
            return nil
        }
        if let productID = identity.productID,
           let serial = normalized(identity.serialNumber) {
            return .serial(vendorID: vendorID, productID: productID, serial: serial)
        }
        guard let productID = identity.productID,
              let name = normalized(identity.name) else {
            return nil
        }
        return .receiver(
            vendorID: vendorID,
            receiverLocationID: receiverLocationID,
            slot: identity.slot,
            kind: identity.kind,
            productID: productID,
            name: name
        )
    }

    static func legacyReceiverDescriptor(
        vendorID: Int?,
        receiverLocationID: Int?,
        kind: ReceiverLogicalDeviceKind,
        productID: Int?,
        name: String?
    ) -> LegacyReceiverDescriptor? {
        guard let vendorID,
              let receiverLocationID,
              let productID,
              let name = normalized(name) else {
            return nil
        }
        return .init(
            vendorID: vendorID,
            receiverLocationID: receiverLocationID,
            kind: kind,
            productID: productID,
            name: name
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

/// Holds original Logitech hardware modes in memory only. A baseline is
/// intentionally never persisted: writing it after a later launch could alter
/// a replaced physical device.
final class LogitechHardwareBaselineStore {
    struct HiResBaseline: Equatable {
        let enabled: Bool
    }

    struct HiResHandle: Hashable {
        fileprivate let target: LogitechHardwareTargetKey
        fileprivate let version: UInt64
    }

    struct HiResClaim: Equatable {
        let baseline: HiResBaseline
        let handle: HiResHandle
    }

    private struct HiResEntry {
        let baseline: HiResBaseline
        let version: UInt64
    }

    private let lock = NSLock()
    private var nextVersion: UInt64 = 0
    private var hiResEntries = [LogitechHardwareTargetKey: HiResEntry]()

    /// First writer wins. A reconstructed Device receives the original mode,
    /// rather than treating LinearMouse's still-applied mode as its baseline.
    func captureHiResBaseline(
        enabled: Bool,
        for target: LogitechHardwareTargetKey
    ) -> HiResClaim {
        lock.withLock {
            if let entry = hiResEntries[target] {
                return .init(
                    baseline: entry.baseline,
                    handle: .init(target: target, version: entry.version)
                )
            }

            nextVersion &+= 1
            let entry = HiResEntry(baseline: .init(enabled: enabled), version: nextVersion)
            hiResEntries[target] = entry
            return .init(
                baseline: entry.baseline,
                handle: .init(target: target, version: entry.version)
            )
        }
    }

    func hiResBaseline(for target: LogitechHardwareTargetKey) -> HiResClaim? {
        lock.withLock {
            guard let entry = hiResEntries[target] else {
                return nil
            }
            return .init(
                baseline: entry.baseline,
                handle: .init(target: target, version: entry.version)
            )
        }
    }

    /// Legacy receivers resolve their logical slot on demand. This conservative
    /// prefix query decides whether that I/O is justified; the exact slot key
    /// is still required to claim a baseline afterwards.
    func hasHiResBaseline(forLegacyReceiver descriptor: LogitechHardwareTargetKey.LegacyReceiverDescriptor) -> Bool {
        lock.withLock {
            hiResEntries.keys.contains { target in
                guard case let .receiver(vendorID, receiverLocationID, _, kind, productID, name) = target else {
                    return false
                }
                return vendorID == descriptor.vendorID
                    && receiverLocationID == descriptor.receiverLocationID
                    && kind == descriptor.kind
                    && productID == descriptor.productID
                    && name == descriptor.name
            }
        }
    }

    /// Removes only the exact baseline generation that was confirmed restored.
    /// A stale session cannot consume an entry captured by a newer session.
    @discardableResult
    func consumeHiResBaseline(_ handle: HiResHandle) -> Bool {
        lock.withLock {
            guard hiResEntries[handle.target]?.version == handle.version else {
                return false
            }
            hiResEntries.removeValue(forKey: handle.target)
            return true
        }
    }
}
