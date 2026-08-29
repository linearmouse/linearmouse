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
        renewLogitechHiResWheelTransportGeneration()
        logitechSettingsQueue.async { [weak self] in
            self?.invalidateLogitechHiResWheel()
        }
        hiResWheelApplyCoordinator.start { [weak self] attempt in
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
        logitechSettingsQueue.async {
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

        logitechSettingsLock.lock()
        let cachedEnabled = cachedHiResWheelEnabled
        logitechSettingsLock.unlock()

        if cachedEnabled == enabled {
            if !verifiesCachedValue || controller.isHighResolutionWheelEnabled() == enabled {
                return enabled
            }
        }

        let capabilities = controller.capabilities()
        guard let result = controller.applyHighResolutionWheelEnabled(enabled) else {
            return nil
        }

        logitechSettingsLock.lock()
        if initialHiResWheelEnabled == nil {
            initialHiResWheelEnabled = result.previousEnabled
        }
        logitechSettingsLock.unlock()

        updateHighResolutionWheelCache(
            enabled: result.appliedEnabled,
            multiplier: result.appliedEnabled ? capabilities.map { Int($0.multiplier) } : nil
        )

        return result.appliedEnabled
    }

    var highResolutionWheelNormalizationMultiplier: Int? {
        logitechSettingsLock.lock()
        defer { logitechSettingsLock.unlock() }

        guard cachedHiResWheelEnabled == true,
              let multiplier = cachedHiResWheelMultiplier,
              multiplier > 1 else {
            return nil
        }

        return multiplier
    }

    func restoreHighResolutionWheel() {
        hiResWheelApplyCoordinator.cancel()
        renewLogitechHiResWheelTransportGeneration()
        logitechSettingsQueue.async { [weak self] in
            self?.invalidateLogitechHiResWheel()
            self?.restoreHighResolutionWheelSynchronously()
        }
    }

    func prepareHighResolutionWheelForReconnect() {
        hiResWheelApplyCoordinator.cancel()
        renewLogitechHiResWheelTransportGeneration()
        logitechSettingsQueue.async { [weak self] in
            guard let self else {
                return
            }

            invalidateLogitechHiResWheel()
            logitechSettingsLock.lock()
            cachedHiResWheelEnabled = nil
            cachedHiResWheelMultiplier = nil
            logitechSettingsLock.unlock()
        }
    }

    private func restoreHighResolutionWheelSynchronously() {
        guard !isRemoved,
              let controller = logitechHiResWheel else {
            clearHighResolutionWheelCache()
            invalidateLogitechHiResWheel()
            return
        }

        logitechSettingsLock.lock()
        let initialEnabled = initialHiResWheelEnabled
        logitechSettingsLock.unlock()

        if let initialEnabled {
            _ = controller.setHighResolutionWheelEnabled(initialEnabled)
        }

        invalidateLogitechHiResWheel()
        clearHighResolutionWheelCache()
    }

    private func clearHighResolutionWheelCache() {
        logitechSettingsLock.lock()
        cachedHiResWheelEnabled = nil
        cachedHiResWheelMultiplier = nil
        initialHiResWheelEnabled = nil
        logitechSettingsLock.unlock()
    }

    private func updateHighResolutionWheelCache(enabled: Bool?, multiplier: Int?) {
        logitechSettingsLock.lock()
        cachedHiResWheelEnabled = enabled
        cachedHiResWheelMultiplier = enabled == true ? multiplier : nil
        logitechSettingsLock.unlock()
    }
}
