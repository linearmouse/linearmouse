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
              let serial = LogitechStableSerial.normalize(serialNumber) else {
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
              let serial = LogitechStableSerial.normalize(identity.serialNumber) else {
            return nil
        }
        return .serial(vendorID: vendorID, serial: serial)
    }
}

/// Holds original Logitech hardware modes in memory only. A baseline is
/// intentionally never persisted: writing it after a later launch could alter
/// a replaced physical device.
final class LogitechHardwareBaselineStore {
    fileprivate final class EntryOwnership {}

    struct DPIBaseline: Equatable {
        let value: Int
    }

    struct DPIHandle: Hashable {
        fileprivate let target: LogitechHardwareTargetKey
        fileprivate let ownership: EntryOwnership

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.target == rhs.target && lhs.ownership === rhs.ownership
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(target)
            hasher.combine(ObjectIdentifier(ownership))
        }

        func belongs(to target: LogitechHardwareTargetKey) -> Bool {
            self.target == target
        }
    }

    struct DPIClaim: Equatable {
        let baseline: DPIBaseline
        let handle: DPIHandle
    }

    struct HiResBaseline: Equatable {
        let enabled: Bool
    }

    struct HiResHandle: Hashable {
        fileprivate let target: LogitechHardwareTargetKey
        fileprivate let ownership: EntryOwnership

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.target == rhs.target && lhs.ownership === rhs.ownership
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(target)
            hasher.combine(ObjectIdentifier(ownership))
        }

        func belongs(to target: LogitechHardwareTargetKey) -> Bool {
            self.target == target
        }
    }

    struct HiResClaim: Equatable {
        let baseline: HiResBaseline
        let handle: HiResHandle
    }

    struct ControlsReportingBaseline: Equatable {
        let flagsRawValue: UInt16
        let mappedControlID: UInt16
    }

    struct ControlsHandle: Hashable {
        fileprivate let target: LogitechHardwareTargetKey
        fileprivate let controlID: UInt16
        fileprivate let ownership: EntryOwnership

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.target == rhs.target
                && lhs.controlID == rhs.controlID
                && lhs.ownership === rhs.ownership
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(target)
            hasher.combine(controlID)
            hasher.combine(ObjectIdentifier(ownership))
        }
    }

    struct ControlsClaim: Equatable {
        let controlID: UInt16
        let baseline: ControlsReportingBaseline
        let handle: ControlsHandle
    }

    private struct Entry<Baseline> {
        let baseline: Baseline
        let ownership = EntryOwnership()
    }

    private typealias DPIEntry = Entry<DPIBaseline>
    private typealias HiResEntry = Entry<HiResBaseline>
    private typealias ControlsEntry = Entry<ControlsReportingBaseline>

    private let lock = NSLock()
    private var dpiEntries = [LogitechHardwareTargetKey: DPIEntry]()
    private var hiResEntries = [LogitechHardwareTargetKey: HiResEntry]()
    private var controlsEntries = [LogitechHardwareTargetKey: [UInt16: ControlsEntry]]()

    /// First writer wins. A reconstructed Device receives the DPI observed
    /// before LinearMouse's first write, not its still-applied value.
    func captureDPIBaseline(
        _ dpi: Int,
        for target: LogitechHardwareTargetKey
    ) -> DPIClaim {
        lock.withLock {
            if let entry = dpiEntries[target] {
                return .init(
                    baseline: entry.baseline,
                    handle: .init(target: target, ownership: entry.ownership)
                )
            }

            let entry = DPIEntry(baseline: .init(value: dpi))
            dpiEntries[target] = entry
            return .init(
                baseline: entry.baseline,
                handle: .init(target: target, ownership: entry.ownership)
            )
        }
    }

    func dpiBaseline(for target: LogitechHardwareTargetKey) -> DPIClaim? {
        lock.withLock {
            guard let entry = dpiEntries[target] else {
                return nil
            }
            return .init(
                baseline: entry.baseline,
                handle: .init(target: target, ownership: entry.ownership)
            )
        }
    }

    /// Removes only the exact baseline entry confirmed restored by its owner.
    @discardableResult
    func consumeDPIBaseline(_ handle: DPIHandle) -> Bool {
        lock.withLock {
            guard dpiEntries[handle.target]?.ownership === handle.ownership else {
                return false
            }
            dpiEntries.removeValue(forKey: handle.target)
            return true
        }
    }

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
                    handle: .init(target: target, ownership: entry.ownership)
                )
            }

            let entry = HiResEntry(baseline: .init(enabled: enabled))
            hiResEntries[target] = entry
            return .init(
                baseline: entry.baseline,
                handle: .init(target: target, ownership: entry.ownership)
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
                handle: .init(target: target, ownership: entry.ownership)
            )
        }
    }

    /// Removes only the exact baseline entry that was confirmed restored.
    /// A stale session cannot consume an entry captured by a newer session.
    @discardableResult
    func consumeHiResBaseline(_ handle: HiResHandle) -> Bool {
        lock.withLock {
            guard hiResEntries[handle.target]?.ownership === handle.ownership else {
                return false
            }
            hiResEntries.removeValue(forKey: handle.target)
            return true
        }
    }

    /// First writer wins per target and control. A resumed monitor therefore
    /// keeps the state observed before its first diversion.
    func captureControlsBaseline(
        _ baseline: ControlsReportingBaseline,
        controlID: UInt16,
        for target: LogitechHardwareTargetKey
    ) -> ControlsClaim {
        lock.withLock {
            if let entry = controlsEntries[target]?[controlID] {
                return .init(
                    controlID: controlID,
                    baseline: entry.baseline,
                    handle: .init(target: target, controlID: controlID, ownership: entry.ownership)
                )
            }

            let entry = ControlsEntry(baseline: baseline)
            controlsEntries[target, default: [:]][controlID] = entry
            return .init(
                controlID: controlID,
                baseline: baseline,
                handle: .init(target: target, controlID: controlID, ownership: entry.ownership)
            )
        }
    }

    func controlsBaseline(
        for target: LogitechHardwareTargetKey,
        controlID: UInt16
    ) -> ControlsClaim? {
        lock.withLock {
            guard let entry = controlsEntries[target]?[controlID] else {
                return nil
            }
            return .init(
                controlID: controlID,
                baseline: entry.baseline,
                handle: .init(target: target, controlID: controlID, ownership: entry.ownership)
            )
        }
    }

    func pendingControlsBaselines(for target: LogitechHardwareTargetKey) -> [ControlsClaim] {
        lock.withLock {
            (controlsEntries[target] ?? [:]).map { controlID, entry in
                .init(
                    controlID: controlID,
                    baseline: entry.baseline,
                    handle: .init(target: target, controlID: controlID, ownership: entry.ownership)
                )
            }
        }
    }

    @discardableResult
    func consumeControlsBaseline(_ handle: ControlsHandle) -> Bool {
        lock.withLock {
            guard controlsEntries[handle.target]?[handle.controlID]?.ownership === handle.ownership else {
                return false
            }
            controlsEntries[handle.target]?.removeValue(forKey: handle.controlID)
            if controlsEntries[handle.target]?.isEmpty == true {
                controlsEntries.removeValue(forKey: handle.target)
            }
            return true
        }
    }
}
