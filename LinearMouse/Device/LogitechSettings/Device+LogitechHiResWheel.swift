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
        hiResWheelApplyCoordinator.start { [weak self] verifiesCachedValue in
            guard let self, !isRemoved else {
                return false
            }

            let applied = applyHighResolutionWheelSynchronously(
                enabled,
                verifiesCachedValue: verifiesCachedValue
            )
            if applied == nil {
                os_log(
                    "Failed to apply configured high-resolution wheel %{public}@ to %{public}@",
                    log: Self.logitechHiResWheelLog,
                    type: .error,
                    enabled ? "enabled" : "disabled",
                    name
                )
            }
            return applied != nil
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
        logitechSettingsQueue.async { [weak self] in
            self?.restoreHighResolutionWheelSynchronously()
        }
    }

    func prepareHighResolutionWheelForReconnect() {
        hiResWheelApplyCoordinator.cancel()
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
