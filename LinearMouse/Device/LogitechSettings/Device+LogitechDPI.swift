// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import os.log

enum LogitechDPIBaselineCapture {
    /// A write is admitted only after the original DPI is already known or a
    /// fresh pre-write read has been accepted by the current target lease.
    static func ensureCaptured(
        hasInitialState: () -> Bool,
        readCurrentDPI: () -> Int?,
        record: (Int) -> Void
    ) -> Bool {
        if hasInitialState() {
            return true
        }
        guard let currentDPI = readCurrentDPI() else {
            return false
        }
        record(currentDPI)
        return hasInitialState()
    }
}

enum LogitechDPIRestoreOperation {
    /// A write acknowledgement is advisory. Only a subsequent read (or the
    /// initial read when no write is needed) confirms restoration.
    static func perform(
        initialDPI: Int,
        shouldContinue: () -> Bool,
        readCurrentDPI: () -> Int?,
        writeDPI: (Int) -> Void
    ) -> Bool {
        guard shouldContinue() else {
            return false
        }
        var confirmedDPI = readCurrentDPI()
        if confirmedDPI != initialDPI {
            guard shouldContinue() else {
                return false
            }
            writeDPI(initialDPI)
            guard shouldContinue() else {
                return false
            }
            confirmedDPI = readCurrentDPI()
        }
        return shouldContinue() && confirmedDPI == initialDPI
    }
}

extension Device {
    private static let logitechDPILog = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HardwareDPI"
    )

    struct HardwareDPIInfo: Equatable {
        let supportsAdjustableDPI: Bool
        let currentDPI: Int?
        let dpiRange: ClosedRange<Int>?
    }

    struct HardwareDPIApplyResult: Equatable {
        enum Outcome: Equatable {
            case applied
            case unsupported
            case cancelled
        }

        let targetDPI: Int?
        let info: HardwareDPIInfo
        let outcome: Outcome

        init(
            targetDPI: Int?,
            info: HardwareDPIInfo,
            outcome: Outcome = .applied
        ) {
            self.targetDPI = targetDPI
            self.info = info
            self.outcome = outcome
        }
    }

    var confirmedLogitechSensorDPI: Int? {
        logitechSession.sensorDPI
    }

    var needsLogitechSensorDPIRestoreRetry: Bool {
        logitechSession.needsDPIRestoreRetry
    }

    func applyConfiguredSensorDPI(_ dpi: Int) {
        logitechSession.startDPIApply { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let start = Date()
            let appliedDPI = applySensorDPISynchronously(
                dpi,
                expectedToken: token,
                verifiesCachedValue: attempt.verifiesCachedValue
            )
            guard !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let phase = attempt.verifiesCachedValue ? "verification" : "apply"
            let duration = Date().timeIntervalSince(start)
            let slot = logitechReceiverRouteSnapshot.map { String($0.slot) } ?? "direct"
            if let appliedDPI {
                os_log(
                    "Logitech hardware DPI %{public}@ succeeded: dpi=%{public}d device=%{public}@ slot=%{public}@ attempt=%{public}d duration=%{public}.3f",
                    log: Self.logitechDPILog,
                    type: .info,
                    phase,
                    appliedDPI,
                    name,
                    slot,
                    attempt.number,
                    duration
                )
                return true
            }

            os_log(
                "Logitech hardware DPI %{public}@ attempt failed: dpi=%{public}d device=%{public}@ slot=%{public}@ attempt=%{public}d final=%{public}@ duration=%{public}.3f",
                log: Self.logitechDPILog,
                type: attempt.isFinal ? .error : .info,
                phase,
                dpi,
                name,
                slot,
                attempt.number,
                attempt.isFinal ? "true" : "false",
                duration
            )
            return false
        }
    }

    func refreshHardwareDPIInfo(completion: @escaping (HardwareDPIInfo) -> Void) {
        logitechSession.perform {
            let info = self.hardwareDPIInfo

            DispatchQueue.main.async {
                completion(info)
            }
        }
    }

    func applyHardwareDPI(_ dpi: Int, completion: @escaping (HardwareDPIApplyResult) -> Void) {
        let cancelledResult = {
            HardwareDPIApplyResult(
                targetDPI: nil,
                info: self.unsupportedHardwareDPIInfo,
                outcome: .cancelled
            )
        }
        let deliver: (HardwareDPIApplyResult, CancellationToken?) -> Void = { result, token in
            DispatchQueue.main.async {
                guard token?.shouldContinue != false, !self.isRemoved else {
                    completion(cancelledResult())
                    return
                }
                completion(result)
            }
        }

        logitechSession.runDPIOperation { token in
            let result: HardwareDPIApplyResult
            if !self.isRemoved, let access = self.logitechAdjustableDPI(for: token) {
                let targetDPI = self.applySensorDPISynchronously(dpi, access: access)
                let currentDPI = targetDPI ?? self.logitechSession.sensorDPI
                result = HardwareDPIApplyResult(
                    targetDPI: targetDPI,
                    info: HardwareDPIInfo(
                        supportsAdjustableDPI: true,
                        currentDPI: currentDPI,
                        dpiRange: access.feature.dpiRange
                    ),
                    outcome: .applied
                )
            } else {
                result = HardwareDPIApplyResult(
                    targetDPI: nil,
                    info: self.unsupportedHardwareDPIInfo,
                    outcome: token.shouldContinue ? .unsupported : .cancelled
                )
            }
            deliver(result, token)
        } onCancelled: {
            deliver(cancelledResult(), nil)
        }
    }

    private var unsupportedHardwareDPIInfo: HardwareDPIInfo {
        HardwareDPIInfo(
            supportsAdjustableDPI: false,
            currentDPI: nil,
            dpiRange: nil
        )
    }

    private var hardwareDPIInfo: HardwareDPIInfo {
        guard !isRemoved, let access = logitechAdjustableDPI else {
            return unsupportedHardwareDPIInfo
        }

        let controller = access.feature
        let currentDPI = controller.currentDPI()
        if let currentDPI {
            logitechSession.updateSensorDPI(currentDPI, for: access)
        }

        return HardwareDPIInfo(
            supportsAdjustableDPI: true,
            currentDPI: currentDPI,
            dpiRange: controller.dpiRange
        )
    }

    private func applySensorDPISynchronously(
        _ dpi: Int,
        expectedToken: CancellationToken,
        verifiesCachedValue: Bool = false
    ) -> Int? {
        guard !isRemoved,
              let access = logitechAdjustableDPI(for: expectedToken) else {
            return nil
        }

        return applySensorDPISynchronously(
            dpi,
            access: access,
            verifiesCachedValue: verifiesCachedValue
        )
    }

    private func applySensorDPISynchronously(
        _ dpi: Int,
        access: LogitechDeviceSession.FeatureAccess<AdjustableDPI>,
        verifiesCachedValue: Bool = false
    ) -> Int? {
        let controller = access.feature
        let targetDPI = controller.supportedDPI(nearestTo: dpi)
        guard controller.canRepresentDPI(targetDPI) else {
            return nil
        }

        _ = seedStoredSensorDPIBaseline(receiverSlot: controller.receiverSlot)
        // Capture before every possible write. A device may apply setDPI even
        // when its acknowledgement is lost.
        guard LogitechDPIBaselineCapture.ensureCaptured(
            hasInitialState: { logitechSession.hasInitialSensorDPIState },
            readCurrentDPI: controller.currentDPI,
            record: { recordSensorDPIBaseline($0, for: access) }
        ), logitechSession.initialSensorDPI(for: access) != nil else {
            return nil
        }

        let cachedDPI = logitechSession.sensorDPI

        if cachedDPI == targetDPI {
            if !verifiesCachedValue || controller.currentDPI() == targetDPI {
                return targetDPI
            }
        }

        guard let appliedDPI = controller.setDPI(targetDPI) else {
            return nil
        }

        logitechSession.updateSensorDPI(appliedDPI, for: access)

        return appliedDPI
    }

    /// Restores one read-back-confirmed DPI baseline. The optional deadline is
    /// checked between HID++ transactions; transport cancellation remains
    /// bound to the immutable session token.
    @discardableResult
    func restoreSensorDPI(deadline: Date? = nil) -> Bool {
        var restored = false
        logitechSession.runDPIOperation(waitUntilFinished: true) { [weak self] token in
            restored = self?.restoreSensorDPISynchronously(
                expectedToken: token,
                deadline: deadline
            ) ?? false
        } onCancelled: {}
        return restored
    }

    /// Asynchronous terminal wrapper used by a bounded teardown coordinator.
    /// It performs a single attempt; the caller owns any retry/deadline policy.
    func restoreSensorDPIForTeardown(
        deadline: Date,
        completion: @escaping (Bool) -> Void
    ) {
        let deliver: (Bool) -> Void = { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        logitechSession.runDPIOperation { [weak self] token in
            deliver(self?.restoreSensorDPISynchronously(
                expectedToken: token,
                deadline: deadline
            ) ?? false)
        } onCancelled: {
            deliver(false)
        }
    }

    /// Stops managing DPI at runtime. Failed attempts retain the original
    /// target-bound value so a later reconciliation or teardown can retry it.
    func stopManagingSensorDPI() {
        logitechSession.startDPIRestore { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }
            return restoreSensorDPISynchronously(expectedToken: token)
        }
    }

    func prepareSensorDPIForReconnect() {
        logitechSession.cancelDPIApply()
        logitechSession.clearSensorDPI()
    }

    private func restoreSensorDPISynchronously(
        expectedToken: CancellationToken,
        deadline: Date? = nil
    ) -> Bool {
        guard shouldContinueSensorDPIRestore(expectedToken, deadline: deadline) else {
            return false
        }

        let hasKnownBaseline = seedStoredSensorDPIBaseline(
            receiverSlot: logitechReceiverRouteSnapshot?.slot
        )
        guard logitechSession.hasInitialSensorDPIState || hasKnownBaseline else {
            logitechSession.invalidateAdjustableDPI(for: expectedToken)
            logitechSession.clearSensorDPI()
            return true
        }

        guard !isRemoved,
              let access = logitechAdjustableDPI(for: expectedToken),
              let initialDPI = logitechSession.initialSensorDPI(for: access)
        else {
            logitechSession.invalidateAdjustableDPI(for: expectedToken)
            return false
        }
        _ = seedStoredSensorDPIBaseline(receiverSlot: access.feature.receiverSlot)

        guard LogitechDPIRestoreOperation.perform(
            initialDPI: initialDPI,
            shouldContinue: {
                shouldContinueSensorDPIRestore(expectedToken, deadline: deadline)
            },
            readCurrentDPI: access.feature.currentDPI,
            writeDPI: { _ = access.feature.setDPI($0) }
        ) else {
            return false
        }

        let commit = logitechSession.completeSensorDPIRestore(dpi: initialDPI, for: access)
        guard case .committed = commit else {
            return false
        }
        consumeStoredSensorDPIBaseline(after: commit)
        return true
    }

    private func shouldContinueSensorDPIRestore(
        _ token: CancellationToken,
        deadline: Date?
    ) -> Bool {
        token.shouldContinue && !isRemoved && deadline.map { Date() < $0 } != false
    }

    @discardableResult
    private func seedStoredSensorDPIBaseline(receiverSlot: UInt8?) -> Bool {
        guard let lease = logitechSession.dpiTargetLease(
            receiverSlot: receiverSlot,
            stableTargetKey: { [weak self] route, slot in
                self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
            }
        ),
            let target = lease.stableTargetKey,
            let claim = logitechHardwareBaselineStore?.dpiBaseline(for: target) else {
            return false
        }
        _ = logitechSession.seedInitialSensorDPI(claim, for: lease)
        return true
    }

    private func recordSensorDPIBaseline(
        _ dpi: Int,
        for access: LogitechDeviceSession.FeatureAccess<AdjustableDPI>
    ) {
        _ = logitechSession.recordInitialSensorDPI(dpi, for: access)
        promoteSensorDPIBaselineIfPossible()
    }

    func promoteSensorDPIBaselineIfPossible() {
        guard let store = logitechHardwareBaselineStore,
              let lease = logitechSession.dpiTargetLease(
                  receiverSlot: nil,
                  stableTargetKey: { [weak self] route, slot in
                      self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
                  }
              ),
              let promotion = logitechSession.dpiBaselinePromotion(for: lease)
        else {
            return
        }

        let claim = store.captureDPIBaseline(promotion.dpi, for: promotion.target)
        _ = logitechSession.attachDPIBaseline(claim, to: promotion)
    }

    private func consumeStoredSensorDPIBaseline(
        after commit: LogitechDeviceSession.DPICommit
    ) {
        guard case let .committed(handle?) = commit,
              let store = logitechHardwareBaselineStore else {
            return
        }
        _ = store.consumeDPIBaseline(handle)
    }
}
