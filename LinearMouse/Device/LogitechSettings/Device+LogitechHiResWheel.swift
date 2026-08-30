// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import os.log

enum LogitechHardwareRestoreRetry {
    static let maximumAttempts = 3

    static func perform(
        operation: () -> Bool,
        wait: (TimeInterval) -> Void
    ) -> Bool {
        var backoff = ExponentialBackoff(initialDelay: 0.1, maximumDelay: 0.4)
        for attempt in 0 ..< maximumAttempts {
            if operation() {
                return true
            }
            if attempt + 1 < maximumAttempts {
                wait(backoff.nextDelay())
            }
        }
        return false
    }
}

enum LogitechHiResBaselineCapture {
    /// A mode write is safe only after the original value belongs to the
    /// current target lease. This mirrors DPI's write-before-ack protection:
    /// a later retry must never capture a value that an earlier unacknowledged
    /// write may already have changed.
    static func ensureCaptured(
        hasInitialState: () -> Bool,
        readCurrentMode: () -> Bool?,
        capture: (Bool) -> Void
    ) -> Bool {
        if hasInitialState() {
            return true
        }
        guard let currentMode = readCurrentMode() else {
            return false
        }
        capture(currentMode)
        return hasInitialState()
    }
}

enum LogitechHiResRestoreOperation {
    /// A HID++ mode-set acknowledgement is advisory. Only a subsequent read
    /// confirms that the original mode is back on the device.
    static func perform(
        initialEnabled: Bool,
        shouldContinue: () -> Bool,
        readCurrentMode: () -> Bool?,
        writeMode: (Bool) -> Void
    ) -> Bool {
        guard shouldContinue() else {
            return false
        }
        var confirmedMode = readCurrentMode()
        if confirmedMode != initialEnabled {
            guard shouldContinue() else {
                return false
            }
            writeMode(initialEnabled)
            guard shouldContinue() else {
                return false
            }
            confirmedMode = readCurrentMode()
        }
        return shouldContinue() && confirmedMode == initialEnabled
    }
}

enum LogitechHiResRestoreAdmission {
    static func needsFeatureAccess(
        hasSessionInitial: Bool,
        hasKnownBaseline: Bool
    ) -> Bool {
        hasSessionInitial || hasKnownBaseline
    }
}

enum LogitechHiResEnabledMultiplier {
    static func resolve(
        cached: Int?,
        load: () -> Int?
    ) -> Int? {
        if let cached, cached > 0 {
            return cached
        }
        guard let loaded = load(), loaded > 0 else {
            return nil
        }
        return loaded
    }
}

extension Device {
    private static let logitechHiResWheelLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HighResolutionWheel"
    )

    struct HighResolutionWheelInfo: Equatable {
        let supportsHighResolutionWheel: Bool
        let enabled: Bool?
        let multiplier: Int?
    }

    var confirmedLogitechHighResolutionWheel: Bool? {
        logitechSession.hiResWheelEnabled
    }

    var needsLogitechHighResolutionWheelRestoreRetry: Bool {
        logitechSession.needsHiResWheelRestoreRetry
    }

    func applyConfiguredHighResolutionWheel(_ enabled: Bool) {
        logitechSession.startHiResWheelApply { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let start = Date()
            let applied = applyHighResolutionWheelSynchronously(
                enabled,
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
            if applied != nil {
                os_log(
                    "Logitech Hi-Res Wheel %{public}@ succeeded: enabled=%{public}@ device=%{public}@ slot=%{public}@ attempt=%{public}d duration=%{public}.3f",
                    log: Self.logitechHiResWheelLog,
                    type: .info,
                    phase,
                    enabled ? "enabled" : "disabled",
                    name,
                    slot,
                    attempt.number,
                    duration
                )
                return true
            }

            os_log(
                "Logitech Hi-Res Wheel %{public}@ attempt failed: enabled=%{public}@ device=%{public}@ slot=%{public}@ attempt=%{public}d final=%{public}@ duration=%{public}.3f",
                log: Self.logitechHiResWheelLog,
                type: attempt.isFinal ? .error : .info,
                phase,
                enabled ? "enabled" : "disabled",
                name,
                slot,
                attempt.number,
                attempt.isFinal ? "true" : "false",
                duration
            )
            return false
        }
    }

    func refreshHighResolutionWheelInfo(completion: @escaping (HighResolutionWheelInfo) -> Void) {
        let deadline = Date().addingTimeInterval(Self.logitechOrdinaryReadTimeout)
        let deliver: (HighResolutionWheelInfo) -> Void = { info in
            DispatchQueue.main.async {
                completion(info)
            }
        }
        logitechSession.runBoundedOrdinaryHardwareRead(deadline: deadline) { shouldContinue in
            deliver(self.highResolutionWheelInfo(deadline: deadline, until: shouldContinue))
        } onCancelled: {
            deliver(self.unsupportedHighResolutionWheelInfo)
        }
    }

    private var unsupportedHighResolutionWheelInfo: HighResolutionWheelInfo {
        HighResolutionWheelInfo(
            supportsHighResolutionWheel: false,
            enabled: nil,
            multiplier: nil
        )
    }

    private func highResolutionWheelInfo(
        deadline: Date,
        until shouldContinue: @escaping () -> Bool
    ) -> HighResolutionWheelInfo {
        guard !isRemoved,
              shouldContinue(),
              let access = logitechHiResWheel(
                  expectedToken: nil,
                  requestDeadline: deadline,
                  operationShouldContinue: shouldContinue
              ) else {
            return unsupportedHighResolutionWheelInfo
        }

        let controller = access.feature
        let capabilities = controller.capabilities(deadline: deadline, until: shouldContinue)
        let enabled = controller.isHighResolutionWheelEnabled(deadline: deadline, until: shouldContinue)
        let multiplier = capabilities.map { Int($0.multiplier) }
        updateHighResolutionWheelCache(enabled: enabled, multiplier: multiplier, for: access)

        return HighResolutionWheelInfo(
            supportsHighResolutionWheel: true,
            enabled: enabled,
            multiplier: multiplier
        )
    }

    private func applyHighResolutionWheelSynchronously(
        _ enabled: Bool,
        expectedToken: CancellationToken,
        verifiesCachedValue: Bool = false,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> Bool? {
        let operationIsAdmitted = {
            operationShouldContinue()
                && self.logitechSession.allowsConfiguredHiResWheelOperation(
                    for: expectedToken
                )
        }
        guard !isRemoved,
              let access = logitechHiResWheel(
                  for: expectedToken,
                  until: operationIsAdmitted
              ) else {
            return nil
        }
        _ = seedStoredHiResWheelBaseline(receiverSlot: access.feature.receiverSlot)

        let controller = access.feature
        let cachedEnabled = logitechSession.hiResWheelEnabled
        let writeIsAdmitted = {
            operationIsAdmitted()
                && self.logitechSession.allowsConfiguredHiResWheelWrite(for: access)
        }

        // Capture before a write is attempted. Some devices can apply a mode
        // change yet lose the reply; waiting for ApplyResult in that case
        // would incorrectly treat the already-managed mode as original.
        guard LogitechHiResBaselineCapture.ensureCaptured(
            hasInitialState: { logitechSession.hasInitialHiResWheelState },
            readCurrentMode: {
                controller.isHighResolutionWheelEnabled(until: writeIsAdmitted)
            },
            capture: { initialEnabled in
                recordHiResWheelBaseline(enabled: initialEnabled, for: access)
            }
        ), logitechSession.initialHiResWheelEnabled(for: access) != nil else {
            return nil
        }

        let resolveEnabledMultiplier = {
            LogitechHiResEnabledMultiplier.resolve(
                cached: self.logitechSession.hiResWheelNormalizationMultiplier
            ) {
                controller.capabilities(until: writeIsAdmitted)
                    .map { Int($0.multiplier) }
            }
        }

        if cachedEnabled == enabled,
           logitechSession.hasInitialHiResWheelState,
           !verifiesCachedValue
           || controller.isHighResolutionWheelEnabled(until: writeIsAdmitted) == enabled {
            guard enabled else {
                return enabled
            }
            guard let multiplier = resolveEnabledMultiplier() else {
                return nil
            }
            updateHighResolutionWheelCache(
                enabled: true,
                multiplier: multiplier,
                for: access
            )
            return enabled
        }

        let multiplier: Int?
        if enabled {
            guard let resolvedMultiplier = resolveEnabledMultiplier() else {
                return nil
            }
            multiplier = resolvedMultiplier
        } else {
            multiplier = nil
        }
        guard let result = controller.applyHighResolutionWheelEnabled(
            enabled,
            until: writeIsAdmitted
        ) else {
            return nil
        }

        recordHiResWheelBaseline(enabled: result.previousEnabled, for: access)

        updateHighResolutionWheelCache(
            enabled: result.appliedEnabled,
            multiplier: result.appliedEnabled ? multiplier : nil,
            for: access
        )

        // A confirmation attempt may rewrite a mode that firmware reset
        // during wake. Require another delayed read before declaring success.
        return verifiesCachedValue ? nil : result.appliedEnabled
    }

    var highResolutionWheelNormalizationMultiplier: Int? {
        logitechSession.hiResWheelNormalizationMultiplier
    }

    func prepareHighResolutionWheelForReconnect() {
        logitechSession.cancelHiResWheelApply()
        logitechSession.clearConfirmedHiResWheelState()
    }

    /// Stops managing this setting. Unlike reconnect preparation, this restores
    /// the target-bound mode that was present before LinearMouse changed it.
    func stopManagingHighResolutionWheel() {
        logitechSession.startHiResWheelRestore { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }
            return restoreHighResolutionWheelSynchronously(
                expectedToken: token,
                confirmsRestore: attempt.verifiesCachedValue,
                until: attempt.shouldContinue
            )
        }
    }

    /// Performs one terminal apply/readback cycle. Retry and the overall
    /// deadline belong to the outer teardown coordinator; this method never
    /// blocks the main thread or starts the normal confirmation scheduler.
    @discardableResult
    func restoreHighResolutionWheelForTeardown(
        expectedToken: CancellationToken,
        attempt: LogitechTerminalHardwareRestoreRetry.Attempt
    ) -> Bool {
        let shouldContinue = {
            expectedToken.shouldContinue
                && attempt.shouldContinue()
                && !self.isRemoved
        }
        guard shouldContinue() else {
            return false
        }

        let hasKnownBaseline = seedStoredHiResWheelBaseline(
            receiverSlot: logitechReceiverRouteSnapshot?.slot
        )
        guard logitechSession.hasInitialHiResWheelState || hasKnownBaseline else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return true
        }

        guard let access = logitechHiResWheel(
            for: expectedToken,
            deadline: attempt.deadline,
            until: shouldContinue
        ),
            let initialEnabled = logitechSession.initialHiResWheelEnabled(for: access)
        else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return false
        }
        _ = seedStoredHiResWheelBaseline(receiverSlot: access.feature.receiverSlot)

        guard LogitechHiResRestoreOperation.perform(
            initialEnabled: initialEnabled,
            shouldContinue: shouldContinue,
            readCurrentMode: {
                access.feature.isHighResolutionWheelEnabled(
                    deadline: attempt.deadline,
                    until: shouldContinue
                )
            },
            writeMode: {
                _ = access.feature.setHighResolutionWheelEnabled(
                    $0,
                    deadline: attempt.deadline,
                    until: shouldContinue
                )
            }
        ) else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return false
        }

        let commit = logitechSession.completeHiResWheelRestore(
            enabled: initialEnabled,
            multiplier: nil,
            for: access
        )
        guard case .committed = commit else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return false
        }
        consumeStoredHiResWheelBaseline(after: commit)
        return true
    }

    private func restoreHighResolutionWheelSynchronously(
        expectedToken: CancellationToken,
        confirmsRestore: Bool = false,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> Bool {
        let operationIsAdmitted = {
            operationShouldContinue()
                && self.logitechSession.allowsConfiguredHiResWheelOperation(
                    for: expectedToken
                )
        }
        let hasKnownBaseline = seedStoredHiResWheelBaseline(
            receiverSlot: logitechReceiverRouteSnapshot?.slot
        )
        guard LogitechHiResRestoreAdmission.needsFeatureAccess(
            hasSessionInitial: logitechSession.hasInitialHiResWheelState,
            hasKnownBaseline: hasKnownBaseline
        ) else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            logitechSession.clearProvisionalHiResWheelMultiplier(for: expectedToken)
            return true
        }

        guard !isRemoved,
              let access = logitechHiResWheel(
                  for: expectedToken,
                  until: operationIsAdmitted
              ) else {
            // Losing transport access is not evidence that the restore worked.
            // Preserve the initial state for a subsequent teardown attempt.
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return false
        }
        _ = seedStoredHiResWheelBaseline(receiverSlot: access.feature.receiverSlot)

        guard logitechSession.hasInitialHiResWheelState else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            logitechSession.clearProvisionalHiResWheelMultiplier(for: expectedToken)
            return true
        }

        let initialEnabled = logitechSession.initialHiResWheelEnabled(for: access)
        guard let initialEnabled else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return false
        }

        let writeIsAdmitted = {
            operationIsAdmitted()
                && self.logitechSession.allowsConfiguredHiResWheelWrite(for: access)
        }

        if confirmsRestore {
            guard let currentEnabled = access.feature.isHighResolutionWheelEnabled(
                until: operationIsAdmitted
            ) else {
                return false
            }
            let currentMultiplier: Int?
            if currentEnabled {
                currentMultiplier = access.feature
                    .capabilities(
                        until: operationIsAdmitted
                    )
                    .map { Int($0.multiplier) }
            } else {
                currentMultiplier = nil
            }
            updateHighResolutionWheelCache(
                enabled: currentEnabled,
                multiplier: currentMultiplier,
                for: access
            )
            if currentEnabled == initialEnabled {
                if initialEnabled, currentMultiplier == nil {
                    return false
                }
                let commit = logitechSession.completeHiResWheelRestore(
                    enabled: initialEnabled,
                    multiplier: currentMultiplier,
                    for: access
                )
                consumeStoredHiResWheelBaseline(after: commit)
                return true
            }

            let restoredMultiplier: Int?
            if initialEnabled {
                guard let capabilities = access.feature.capabilities(
                    until: operationIsAdmitted
                ) else {
                    return false
                }
                restoredMultiplier = Int(capabilities.multiplier)
            } else {
                restoredMultiplier = nil
            }

            // The device can reset its mode after accepting an early write.
            // Reapply it and let the coordinator schedule another read.
            guard access.feature.setHighResolutionWheelEnabled(
                initialEnabled,
                until: writeIsAdmitted
            ) == initialEnabled else {
                return false
            }
            updateHighResolutionWheelCache(
                enabled: initialEnabled,
                multiplier: restoredMultiplier,
                for: access
            )
            return false
        }

        let restoredMultiplier: Int?
        if initialEnabled {
            guard let capabilities = access.feature.capabilities(
                until: operationIsAdmitted
            ) else {
                // Enabling Hi-Res without its multiplier would make event
                // normalization inconsistent with the hardware. Keep the
                // current mode/cache and retain initial state for a later try.
                logitechSession.invalidateHiResWheel(for: expectedToken)
                return false
            }
            restoredMultiplier = Int(capabilities.multiplier)
        } else {
            restoredMultiplier = nil
        }

        let restored = access.feature.setHighResolutionWheelEnabled(
            initialEnabled,
            until: writeIsAdmitted
        ) == initialEnabled
        logitechSession.invalidateHiResWheel(for: expectedToken)
        if restored {
            // The write is only an apply-phase result. Retain the initial
            // target until a later confirmation reads it back.
            updateHighResolutionWheelCache(
                enabled: initialEnabled,
                multiplier: restoredMultiplier,
                for: access
            )
        } else {
            // The device may be temporarily asleep. Keep the original state
            // so a later lifecycle teardown can still restore it.
        }
        return restored
    }

    @discardableResult
    private func seedStoredHiResWheelBaseline(receiverSlot: UInt8?) -> Bool {
        guard let lease = logitechSession.hiResWheelTargetLease(
            receiverSlot: receiverSlot,
            stableTargetKey: { [weak self] route, slot in
                self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
            }
        ),
            let target = lease.stableTargetKey,
            let claim = logitechHardwareBaselineStore?.hiResBaseline(for: target) else {
            return false
        }
        _ = logitechSession.seedInitialHiResWheelState(claim, for: lease)
        return true
    }

    private func recordHiResWheelBaseline(
        enabled: Bool,
        for access: LogitechDeviceSession.FeatureAccess<HiResWheel>
    ) {
        _ = logitechSession.recordInitialHiResWheelState(enabled: enabled, for: access)
        // Discovery may enrich serial metadata while the HID read is in
        // flight, so promotion always uses a freshly validated lease.
        promoteHiResWheelBaselineIfPossible()
    }

    func promoteHiResWheelBaselineIfPossible() {
        guard let store = logitechHardwareBaselineStore,
              let lease = logitechSession.hiResWheelTargetLease(
                  receiverSlot: nil,
                  stableTargetKey: { [weak self] route, slot in
                      self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
                  }
              ),
              let promotion = logitechSession.hiResBaselinePromotion(for: lease)
        else {
            return
        }

        let claim = store.captureHiResBaseline(enabled: promotion.enabled, for: promotion.target)
        _ = logitechSession.attachHiResBaseline(claim, to: promotion)
    }

    private func consumeStoredHiResWheelBaseline(
        after commit: LogitechDeviceSession.HiResWheelCommit
    ) {
        guard case let .committed(handle?) = commit,
              let store = logitechHardwareBaselineStore else {
            return
        }
        _ = store.consumeHiResBaseline(handle)
    }

    private func updateHighResolutionWheelCache(
        enabled: Bool?,
        multiplier: Int?,
        for access: LogitechDeviceSession.FeatureAccess<HiResWheel>
    ) {
        logitechSession.updateHiResWheelState(enabled: enabled, multiplier: multiplier, for: access)
    }
}
