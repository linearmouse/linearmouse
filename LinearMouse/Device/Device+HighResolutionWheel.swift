// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Device {
    private static let highResolutionWheelQueue = DispatchQueue(
        label: "app.linearmouse.high-resolution-wheel",
        qos: .userInitiated
    )

    struct HighResolutionWheelInfo: Equatable {
        let supportsHighResolutionWheel: Bool
        let enabled: Bool?
        let multiplier: Int?
    }

    func applyConfiguredHighResolutionWheel(_ enabled: Bool) {
        Self.highResolutionWheelQueue.async {
            _ = self.applyHighResolutionWheelSynchronously(enabled)
        }
    }

    func refreshHighResolutionWheelInfo(completion: @escaping (HighResolutionWheelInfo) -> Void) {
        Self.highResolutionWheelQueue.async {
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
        guard !isRemoved, let controller = logitechHighResolutionWheelController else {
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

    private func applyHighResolutionWheelSynchronously(_ enabled: Bool) -> Bool? {
        guard !isRemoved,
              let controller = logitechHighResolutionWheelController else {
            return nil
        }

        let capabilities = controller.capabilities()
        let currentEnabled = controller.isHighResolutionWheelEnabled()

        highResolutionWheelLock.lock()
        if initialHighResolutionWheelEnabled == nil {
            initialHighResolutionWheelEnabled = currentEnabled
        }
        if cachedHighResolutionWheelEnabled == enabled {
            cachedHighResolutionWheelMultiplier = enabled ? capabilities.map { Int($0.multiplier) } : nil
            highResolutionWheelLock.unlock()
            return enabled
        }
        highResolutionWheelLock.unlock()

        guard let applied = controller.setHighResolutionWheelEnabled(enabled) else {
            return nil
        }

        updateHighResolutionWheelCache(
            enabled: applied,
            multiplier: applied ? capabilities.map { Int($0.multiplier) } : nil
        )

        return applied
    }

    var highResolutionWheelNormalizationMultiplier: Int? {
        highResolutionWheelLock.lock()
        defer { highResolutionWheelLock.unlock() }

        guard cachedHighResolutionWheelEnabled == true,
              let multiplier = cachedHighResolutionWheelMultiplier,
              multiplier > 1 else {
            return nil
        }

        return multiplier
    }

    func restoreHighResolutionWheel() {
        Self.highResolutionWheelQueue.sync {
            self.restoreHighResolutionWheelSynchronously()
        }
    }

    private func restoreHighResolutionWheelSynchronously() {
        guard !isRemoved,
              let controller = logitechHighResolutionWheelController else {
            clearHighResolutionWheelCache()
            return
        }

        highResolutionWheelLock.lock()
        let initialEnabled = initialHighResolutionWheelEnabled
        highResolutionWheelLock.unlock()

        if let initialEnabled {
            _ = controller.setHighResolutionWheelEnabled(initialEnabled)
        }

        clearHighResolutionWheelCache()
    }

    private func clearHighResolutionWheelCache() {
        highResolutionWheelLock.lock()
        cachedHighResolutionWheelEnabled = nil
        cachedHighResolutionWheelMultiplier = nil
        initialHighResolutionWheelEnabled = nil
        highResolutionWheelLock.unlock()
    }

    private func updateHighResolutionWheelCache(enabled: Bool?, multiplier: Int?) {
        highResolutionWheelLock.lock()
        cachedHighResolutionWheelEnabled = enabled
        cachedHighResolutionWheelMultiplier = enabled == true ? multiplier : nil
        highResolutionWheelLock.unlock()
    }
}
