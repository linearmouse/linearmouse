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

    /// Suspends ordinary Logitech setting I/O without restoring or consuming
    /// the target-bound DPI and wheel baselines.
    func suspendLogitechSettings() -> LogitechHardwareSuspension? {
        logitechSession.suspendHardware()
    }

    /// Resumes only the exact suspension still owned by this device session.
    /// A terminal teardown that superseded it makes this a no-op.
    @discardableResult
    func resumeLogitechSettings(from suspension: LogitechHardwareSuspension) -> Bool {
        logitechSession.resumeHardware(from: suspension)
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
                verifiesCachedValue: attempt.verifiesCachedValue,
                until: attempt.shouldContinue
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
        let deadline = Date().addingTimeInterval(Self.logitechOrdinaryReadTimeout)
        let deliver: (HardwareDPIInfo) -> Void = { info in
            DispatchQueue.main.async {
                completion(info)
            }
        }
        logitechSession.runBoundedOrdinaryHardwareRead(deadline: deadline) { shouldContinue in
            deliver(self.hardwareDPIInfo(deadline: deadline, until: shouldContinue))
        } onCancelled: {
            deliver(self.unsupportedHardwareDPIInfo)
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

    private func hardwareDPIInfo(
        deadline: Date,
        until shouldContinue: @escaping () -> Bool
    ) -> HardwareDPIInfo {
        guard !isRemoved,
              shouldContinue(),
              let access = logitechAdjustableDPI(
                  expectedToken: nil,
                  requestDeadline: deadline,
                  operationShouldContinue: shouldContinue
              ) else {
            return unsupportedHardwareDPIInfo
        }

        let controller = access.feature
        let currentDPI = controller.currentDPI(deadline: deadline, until: shouldContinue)
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
        verifiesCachedValue: Bool = false,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> Int? {
        let operationIsAdmitted = {
            operationShouldContinue()
                && self.logitechSession.allowsConfiguredDPIOperation(
                    for: expectedToken
                )
        }
        guard !isRemoved,
              let access = logitechAdjustableDPI(
                  for: expectedToken,
                  until: operationIsAdmitted
              ) else {
            return nil
        }

        return applySensorDPISynchronously(
            dpi,
            access: access,
            verifiesCachedValue: verifiesCachedValue,
            until: operationIsAdmitted
        )
    }

    private func applySensorDPISynchronously(
        _ dpi: Int,
        access: LogitechDeviceSession.FeatureAccess<AdjustableDPI>,
        verifiesCachedValue: Bool = false,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> Int? {
        let controller = access.feature
        let targetDPI = controller.supportedDPI(nearestTo: dpi)
        guard controller.canRepresentDPI(targetDPI) else {
            return nil
        }

        let operationIsAdmitted = {
            operationShouldContinue()
                && self.logitechSession.allowsConfiguredDPIWrite(for: access)
        }

        _ = seedStoredSensorDPIBaseline(receiverSlot: controller.receiverSlot)
        // Capture before every possible write. A device may apply setDPI even
        // when its acknowledgement is lost.
        guard LogitechDPIBaselineCapture.ensureCaptured(
            hasInitialState: { logitechSession.hasInitialSensorDPIState },
            readCurrentDPI: {
                controller.currentDPI(until: operationIsAdmitted)
            },
            record: { recordSensorDPIBaseline($0, for: access) }
        ), logitechSession.initialSensorDPI(for: access) != nil else {
            return nil
        }

        let cachedDPI = logitechSession.sensorDPI

        if cachedDPI == targetDPI {
            if !verifiesCachedValue
                || controller.currentDPI(until: operationIsAdmitted) == targetDPI {
                return targetDPI
            }
        }

        guard let appliedDPI = controller.setDPI(
            targetDPI,
            until: operationIsAdmitted
        ) else {
            return nil
        }

        logitechSession.updateSensorDPI(appliedDPI, for: access)

        // A confirmation attempt may rewrite a value that firmware reset
        // during wake. Do not let that write ACK finish confirmation: the
        // coordinator must schedule another delayed read of the new value.
        return verifiesCachedValue ? nil : appliedDPI
    }

    /// Synchronous only with respect to the Logitech session queue. The
    /// terminal coordinator invokes it from that background queue, never from
    /// AppKit's main thread.
    @discardableResult
    func restoreSensorDPIForTeardown(
        expectedToken: CancellationToken,
        attempt: LogitechTerminalHardwareRestoreRetry.Attempt
    ) -> Bool {
        let shouldContinue = attempt.shouldContinue
        let restored = restoreSensorDPISynchronously(
            expectedToken: expectedToken,
            deadline: attempt.deadline,
            until: shouldContinue
        ) { _ in shouldContinue() }
        if !restored {
            // A receiver monitor may have replaced its shared channel while
            // this feature still retained the old transport. Keep the target
            // baseline and token, but force the next bounded attempt to bind a
            // fresh feature to the current channel.
            logitechSession.invalidateAdjustableDPI(for: expectedToken)
        }
        return restored
    }

    /// Stops managing DPI at runtime. Failed attempts retain the original
    /// target-bound value so a later reconciliation or teardown can retry it.
    func stopManagingSensorDPI() {
        logitechSession.startDPIRestore { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }
            return restoreSensorDPISynchronously(
                expectedToken: token,
                until: attempt.shouldContinue
            )
        }
    }

    func prepareSensorDPIForReconnect() {
        logitechSession.cancelDPIApply()
        logitechSession.clearSensorDPI()
    }

    private func restoreSensorDPISynchronously(
        expectedToken: CancellationToken,
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool = { true },
        writeAdmission: ((LogitechDeviceSession.FeatureAccess<AdjustableDPI>) -> Bool)? = nil
    ) -> Bool {
        let shouldContinue = {
            self.shouldContinueSensorDPIRestore(
                expectedToken,
                deadline: deadline,
                operationShouldContinue: operationShouldContinue
            )
        }
        guard shouldContinue() else {
            return false
        }
        let isBoundedLifecycleRestore = writeAdmission != nil
        let featureIOShouldContinue = {
            shouldContinue()
                && (isBoundedLifecycleRestore
                    || self.logitechSession.allowsConfiguredDPIOperation(
                        for: expectedToken
                    ))
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
              let access = logitechAdjustableDPI(
                  for: expectedToken,
                  deadline: deadline,
                  loadsSupportedDPI: false,
                  until: featureIOShouldContinue
              ),
              let initialDPI = logitechSession.initialSensorDPI(for: access)
        else {
            logitechSession.invalidateAdjustableDPI(for: expectedToken)
            return false
        }
        _ = seedStoredSensorDPIBaseline(receiverSlot: access.feature.receiverSlot)

        let writeIsAdmitted = {
            shouldContinue()
                && (writeAdmission?(access)
                    ?? self.logitechSession.allowsConfiguredDPIWrite(for: access))
        }

        guard LogitechDPIRestoreOperation.perform(
            initialDPI: initialDPI,
            shouldContinue: shouldContinue,
            readCurrentDPI: {
                access.feature.currentDPI(
                    deadline: deadline,
                    until: featureIOShouldContinue
                )
            },
            writeDPI: {
                _ = access.feature.setDPIExactly(
                    $0,
                    deadline: deadline,
                    until: writeIsAdmitted
                )
            }
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
        deadline: Date?,
        operationShouldContinue: () -> Bool
    ) -> Bool {
        token.shouldContinue
            && operationShouldContinue()
            && !isRemoved
            && deadline.map { Date() < $0 } != false
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
