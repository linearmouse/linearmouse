// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import os.log

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

        let controller = access.feature
        let cachedEnabled = logitechSession.hiResWheelEnabled

        if cachedEnabled == enabled {
            if !verifiesCachedValue || controller.isHighResolutionWheelEnabled() == enabled {
                return enabled
            }
        }

        let capabilities = controller.capabilities()
        guard let result = controller.applyHighResolutionWheelEnabled(enabled) else {
            return nil
        }

        logitechSession.recordInitialHiResWheelState(enabled: result.previousEnabled, for: access)

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
            restoreHighResolutionWheelSynchronously(
                expectedToken: token,
                trackingRestoredState: trackingRestoredState
            )
        }
    }

    func prepareHighResolutionWheelForReconnect() {
        logitechSession.cancelHiResWheelApply()
        logitechSession.clearHiResWheelState(includingInitialState: false)
    }

    /// Stops managing this setting. Unlike reconnect preparation, this restores
    /// the target-bound mode that was present before LinearMouse changed it.
    func stopManagingHighResolutionWheel() {
        restoreHighResolutionWheel(
            waitUntilFinished: false,
            trackingRestoredState: true
        )
    }

    private func restoreHighResolutionWheelSynchronously(
        expectedToken: CancellationToken,
        trackingRestoredState: Bool
    ) {
        guard logitechSession.hasInitialHiResWheelState else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            if !trackingRestoredState {
                clearHighResolutionWheelCache()
            }
            return
        }

        guard !isRemoved,
              let access = logitechHiResWheel(for: expectedToken) else {
            // Losing transport access is not evidence that the restore worked.
            // Preserve the initial state for a subsequent teardown attempt.
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return
        }

        let initialEnabled = logitechSession.initialHiResWheelEnabled(
            requiresReceiverRoute: LogitechReceiverRouteResolver.requiresDiscovery(for: pointerDevice),
            receiverSlot: access.feature.receiverSlot
        )
        guard let initialEnabled else {
            logitechSession.invalidateHiResWheel(for: expectedToken)
            return
        }

        let restoredMultiplier: Int?
        if trackingRestoredState, initialEnabled {
            guard let capabilities = access.feature.capabilities() else {
                // Enabling Hi-Res without its multiplier would make event
                // normalization inconsistent with the hardware. Keep the
                // current mode/cache and retain initial state for a later try.
                logitechSession.invalidateHiResWheel(for: expectedToken)
                return
            }
            restoredMultiplier = Int(capabilities.multiplier)
        } else {
            restoredMultiplier = nil
        }

        let restored = access.feature.setHighResolutionWheelEnabled(initialEnabled) == initialEnabled
        logitechSession.invalidateHiResWheel(for: expectedToken)
        if restored {
            if trackingRestoredState {
                logitechSession.completeHiResWheelRestore(
                    enabled: initialEnabled,
                    multiplier: restoredMultiplier,
                    for: access
                )
            } else {
                clearHighResolutionWheelCache()
            }
        } else {
            // The device may be temporarily asleep. Keep the original state
            // so a later lifecycle teardown can still restore it.
        }
    }

    private func clearHighResolutionWheelCache() {
        logitechSession.clearHiResWheelState(includingInitialState: true)
    }

    private func updateHighResolutionWheelCache(
        enabled: Bool?,
        multiplier: Int?,
        for access: LogitechDeviceSession.FeatureAccess<HiResWheel>
    ) {
        logitechSession.updateHiResWheelState(enabled: enabled, multiplier: multiplier, for: access)
    }
}
