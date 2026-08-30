// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
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

    func applyConfiguredHighResolutionWheel(_ enabled: Bool) {
        logitechSession.renewHiResWheelTransport()
        logitechSession.hiResWheelApplyCoordinator.start { [weak self] attempt in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let start = Date()
            let applied = applyHighResolutionWheelSynchronously(
                enabled,
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
        logitechSession.queue.async {
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
        guard !isRemoved, let controller = logitechHiResWheel else {
            return unsupportedHighResolutionWheelInfo
        }

        let capabilities = controller.capabilities()
        let enabled = controller.isHighResolutionWheelEnabled()
        let multiplier = capabilities.map { Int($0.multiplier) }
        updateHighResolutionWheelCache(enabled: enabled, multiplier: multiplier)

        return HighResolutionWheelInfo(
            supportsHighResolutionWheel: true,
            enabled: enabled,
            multiplier: multiplier
        )
    }

    private func applyHighResolutionWheelSynchronously(
        _ enabled: Bool,
        verifiesCachedValue: Bool = false
    ) -> Bool? {
        guard !isRemoved,
              let controller = logitechHiResWheel else {
            return nil
        }

        let cachedEnabled = logitechSession.withState { $0.hiResWheelEnabled }

        if cachedEnabled == enabled {
            if !verifiesCachedValue || controller.isHighResolutionWheelEnabled() == enabled {
                return enabled
            }
        }

        let capabilities = controller.capabilities()
        guard let result = controller.applyHighResolutionWheelEnabled(enabled) else {
            return nil
        }

        logitechSession.withState { state in
            if state.initialHiResWheelEnabled == nil {
                state.initialHiResWheelEnabled = result.previousEnabled
            }
        }

        updateHighResolutionWheelCache(
            enabled: result.appliedEnabled,
            multiplier: result.appliedEnabled ? capabilities.map { Int($0.multiplier) } : nil
        )

        return result.appliedEnabled
    }

    var highResolutionWheelNormalizationMultiplier: Int? {
        let multiplier = logitechSession.withState { state -> Int? in
            guard state.hiResWheelEnabled == true,
                  let multiplier = state.hiResWheelMultiplier else {
                return nil
            }
            return multiplier
        }
        guard let multiplier, multiplier > 1 else {
            return nil
        }

        return multiplier
    }

    func restoreHighResolutionWheel() {
        logitechSession.hiResWheelApplyCoordinator.cancel()
        logitechSession.renewHiResWheelTransport()
        logitechSession.queue.async { [weak self] in
            self?.restoreHighResolutionWheelSynchronously()
        }
    }

    func prepareHighResolutionWheelForReconnect() {
        logitechSession.hiResWheelApplyCoordinator.cancel()
        logitechSession.renewHiResWheelTransport()
        logitechSession.withState {
            $0.hiResWheelEnabled = nil
            $0.hiResWheelMultiplier = nil
        }
    }

    private func restoreHighResolutionWheelSynchronously() {
        guard !isRemoved,
              let controller = logitechHiResWheel else {
            clearHighResolutionWheelCache()
            logitechSession.invalidateHiResWheel()
            return
        }

        let initialEnabled = logitechSession.withState { $0.initialHiResWheelEnabled }

        if let initialEnabled {
            _ = controller.setHighResolutionWheelEnabled(initialEnabled)
        }

        logitechSession.invalidateHiResWheel()
        clearHighResolutionWheelCache()
    }

    private func clearHighResolutionWheelCache() {
        logitechSession.withState {
            $0.hiResWheelEnabled = nil
            $0.hiResWheelMultiplier = nil
            $0.initialHiResWheelEnabled = nil
        }
    }

    private func updateHighResolutionWheelCache(enabled: Bool?, multiplier: Int?) {
        logitechSession.withState {
            $0.hiResWheelEnabled = enabled
            $0.hiResWheelMultiplier = enabled == true ? multiplier : nil
        }
    }
}
