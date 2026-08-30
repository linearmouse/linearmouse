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
    static func captureIfNeeded(
        hasInitialState: Bool,
        readCurrentMode: () -> Bool?,
        capture: (Bool) -> Void
    ) {
        guard !hasInitialState,
              let currentMode = readCurrentMode() else {
            return
        }
        capture(currentMode)
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

enum LogitechHiResSleepRestorePolicy: Equatable {
    case preserveStoreBaseline
    case restoreBestEffort
    case skip

    static func resolve(hasSessionInitial: Bool, hasStoreBaseline: Bool) -> Self {
        guard hasSessionInitial else {
            return .skip
        }
        return hasStoreBaseline ? .preserveStoreBaseline : .restoreBestEffort
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
                verifiesCachedValue: attempt.verifiesCachedValue
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
        logitechSession.perform {
            let info = self.highResolutionWheelInfo

            DispatchQueue.main.async {
                completion(info)
            }
        }
    }

    private var unsupportedHighResolutionWheelInfo: HighResolutionWheelInfo {
        HighResolutionWheelInfo(
            supportsHighResolutionWheel: false,
            enabled: nil,
            multiplier: nil
        )
    }

    private var highResolutionWheelInfo: HighResolutionWheelInfo {
        guard !isRemoved, let access = logitechHiResWheel else {
            return unsupportedHighResolutionWheelInfo
        }

        let controller = access.feature
        let capabilities = controller.capabilities()
        let enabled = controller.isHighResolutionWheelEnabled()
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
        verifiesCachedValue: Bool = false
    ) -> Bool? {
        guard !isRemoved,
              let access = logitechHiResWheel(for: expectedToken) else {
            return nil
        }
        _ = seedStoredHiResWheelBaseline(receiverSlot: access.feature.receiverSlot)

        let controller = access.feature
        let cachedEnabled = logitechSession.hiResWheelEnabled

        // Capture before a write is attempted. Some devices can apply a mode
        // change yet lose the reply; waiting for ApplyResult in that case
        // would incorrectly treat the already-managed mode as original.
        LogitechHiResBaselineCapture.captureIfNeeded(
            hasInitialState: logitechSession.hasInitialHiResWheelState,
            readCurrentMode: controller.isHighResolutionWheelEnabled
        ) { initialEnabled in
            recordHiResWheelBaseline(enabled: initialEnabled, for: access)
        }

        if cachedEnabled == enabled, logitechSession.hasInitialHiResWheelState {
            if !verifiesCachedValue || controller.isHighResolutionWheelEnabled() == enabled {
                return enabled
            }
        }

        let capabilities = controller.capabilities()
        guard let result = controller.applyHighResolutionWheelEnabled(enabled) else {
            return nil
        }

        recordHiResWheelBaseline(enabled: result.previousEnabled, for: access)

        updateHighResolutionWheelCache(
            enabled: result.appliedEnabled,
            multiplier: result.appliedEnabled ? capabilities.map { Int($0.multiplier) } : nil,
            for: access
        )

        return result.appliedEnabled
    }

    var highResolutionWheelNormalizationMultiplier: Int? {
        logitechSession.hiResWheelNormalizationMultiplier
    }

    func restoreHighResolutionWheel(
        waitUntilFinished: Bool,
        trackingRestoredState: Bool = false
    ) {
        logitechSession.runHiResWheelOperation(waitUntilFinished: waitUntilFinished) { [weak self] token in
            guard let self else {
                return
            }
            if waitUntilFinished {
                let restored = LogitechHardwareRestoreRetry.perform(
                    operation: {
                        token.shouldContinue && self.restoreHighResolutionWheelSynchronously(
                            expectedToken: token,
                            trackingRestoredState: trackingRestoredState
                        )
                    },
                    wait: self.pumpMainRunLoop
                )
                if !restored, token.shouldContinue {
                    os_log(
                        "Logitech Hi-Res Wheel lifecycle restore exhausted retry budget: device=%{public}@",
                        log: Self.logitechHiResWheelLog,
                        type: .error,
                        self.name
                    )
                }
            } else {
                _ = restoreHighResolutionWheelSynchronously(
                    expectedToken: token,
                    trackingRestoredState: trackingRestoredState
                )
            }
        }
    }

    func prepareHighResolutionWheelForReconnect() {
        logitechSession.cancelHiResWheelApply()
        logitechSession.clearHiResWheelState(includingInitialState: false)
    }

    func restoreHighResolutionWheelForSleep() {
        switch LogitechHiResSleepRestorePolicy.resolve(
            hasSessionInitial: logitechSession.hasInitialHiResWheelState,
            hasStoreBaseline: logitechSession.hasStoredHiResWheelBaseline
        ) {
        case .preserveStoreBaseline, .skip:
            prepareHighResolutionWheelForReconnect()
        case .restoreBestEffort:
            restoreHighResolutionWheel(waitUntilFinished: true)
        }
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
                trackingRestoredState: true,
                confirmsRestore: attempt.verifiesCachedValue
            )
        }
    }

    private func restoreHighResolutionWheelSynchronously(
        expectedToken: CancellationToken,
        trackingRestoredState: Bool,
        confirmsRestore: Bool = false
    ) -> Bool {
        let hasKnownBaseline = seedStoredHiResWheelBaseline(
            receiverSlot: logitechReceiverRouteSnapshot?.slot
        )
        guard LogitechHiResRestoreAdmission.needsFeatureAccess(
            hasSessionInitial: logitechSession.hasInitialHiResWheelState,
            hasKnownBaseline: hasKnownBaseline
        ) else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            if !trackingRestoredState {
                clearHighResolutionWheelCache()
            }
            return true
        }

        guard !isRemoved,
              let access = logitechHiResWheel(for: expectedToken) else {
            // Losing transport access is not evidence that the restore worked.
            // Preserve the initial state for a subsequent teardown attempt.
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return false
        }
        _ = seedStoredHiResWheelBaseline(receiverSlot: access.feature.receiverSlot)

        guard logitechSession.hasInitialHiResWheelState else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            if !trackingRestoredState {
                clearHighResolutionWheelCache()
            }
            return true
        }

        let initialEnabled = logitechSession.initialHiResWheelEnabled(for: access)
        guard let initialEnabled else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return false
        }

        if confirmsRestore {
            guard let currentEnabled = access.feature.isHighResolutionWheelEnabled() else {
                return false
            }
            let currentMultiplier: Int?
            if currentEnabled {
                currentMultiplier = access.feature.capabilities().map { Int($0.multiplier) }
            } else {
                currentMultiplier = nil
            }
            updateHighResolutionWheelCache(
                enabled: currentEnabled,
                multiplier: currentMultiplier,
                for: access
            )
            if currentEnabled == initialEnabled {
                if trackingRestoredState, initialEnabled, currentMultiplier == nil {
                    return false
                }
                if trackingRestoredState {
                    let commit = logitechSession.completeHiResWheelRestore(
                        enabled: initialEnabled,
                        multiplier: currentMultiplier,
                        for: access
                    )
                    consumeStoredHiResWheelBaseline(after: commit)
                }
                return true
            }

            let restoredMultiplier: Int?
            if trackingRestoredState, initialEnabled {
                guard let capabilities = access.feature.capabilities() else {
                    return false
                }
                restoredMultiplier = Int(capabilities.multiplier)
            } else {
                restoredMultiplier = nil
            }

            // The device can reset its mode after accepting an early write.
            // Reapply it and let the coordinator schedule another read.
            guard access.feature.setHighResolutionWheelEnabled(initialEnabled) == initialEnabled else {
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
        if trackingRestoredState, initialEnabled {
            guard let capabilities = access.feature.capabilities() else {
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

        let restored = access.feature.setHighResolutionWheelEnabled(initialEnabled) == initialEnabled
        logitechSession.invalidateHiResWheel(for: expectedToken)
        if restored {
            if trackingRestoredState {
                // The write is only an apply-phase result. Retain the initial
                // target until a later confirmation reads it back.
                updateHighResolutionWheelCache(
                    enabled: initialEnabled,
                    multiplier: restoredMultiplier,
                    for: access
                )
            } else {
                let commit = logitechSession.consumeHiResWheelState(for: access)
                consumeStoredHiResWheelBaseline(after: commit)
            }
        } else {
            // The device may be temporarily asleep. Keep the original state
            // so a later lifecycle teardown can still restore it.
        }
        return restored
    }

    private func clearHighResolutionWheelCache() {
        logitechSession.clearHiResWheelState(includingInitialState: true)
    }

    private func pumpMainRunLoop(for interval: TimeInterval) {
        guard Thread.isMainThread else {
            Thread.sleep(forTimeInterval: interval)
            return
        }

        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, min(0.01, deadline.timeIntervalSinceNow), true)
        }
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
