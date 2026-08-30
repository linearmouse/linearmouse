// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// A process-lifetime identity for hardware state that must survive a
/// PointerDevice/session rebuild (notably across system sleep).
enum LogitechHardwareTargetKey: Hashable {
    case serial(vendorID: Int, serial: String)

    static func direct(
        transport _: String?,
        locationID _: Int?,
        vendorID: Int?,
        productID _: Int?,
        serialNumber: String?,
        name _: String?
    ) -> Self? {
        guard let vendorID,
              let serial = normalized(serialNumber) else {
            return nil
        }
        return .serial(vendorID: vendorID, serial: serial)
    }

    static func receiver(
        vendorID: Int?,
        receiverLocationID _: Int?,
        identity: ReceiverLogicalDeviceIdentity
    ) -> Self? {
        guard let vendorID,
              let serial = normalized(identity.serialNumber) else {
            return nil
        }
        return .serial(vendorID: vendorID, serial: serial)
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
