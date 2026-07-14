// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Device {
    private enum HighResolutionWheelApplyRetry {
        static let maxAttempts = 8
        static let delay: TimeInterval = 5
    }

    private static let highResolutionWheelQueue = DispatchQueue(
        label: "app.linearmouse.high-resolution-wheel",
        qos: .default
    )

    struct HighResolutionWheelInfo: Equatable {
        let supportsHighResolutionWheel: Bool
        let enabled: Bool?
        let multiplier: Int?
    }

    func applyConfiguredHighResolutionWheel(_ enabled: Bool) {
        let requestID = nextHighResolutionWheelApplyRequestID()
        Self.highResolutionWheelQueue.async {
            self.applyHighResolutionWheel(enabled, requestID: requestID, attempt: 1)
        }
    }

    private func applyHighResolutionWheel(_ enabled: Bool, requestID: UUID, attempt: Int) {
        guard isCurrentHighResolutionWheelApplyRequest(requestID), !isRemoved else {
            return
        }

        guard applyHighResolutionWheelSynchronously(enabled) == nil else {
            return
        }

        guard attempt < HighResolutionWheelApplyRetry.maxAttempts else {
            return
        }

        Self.highResolutionWheelQueue
            .asyncAfter(deadline: .now() + HighResolutionWheelApplyRetry.delay) { [weak self] in
                self?.applyHighResolutionWheel(enabled, requestID: requestID, attempt: attempt + 1)
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
            invalidateLogitechHighResolutionWheelController()
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
        cancelHighResolutionWheelApplyRequests()
        Self.highResolutionWheelQueue.sync {
            self.restoreHighResolutionWheelSynchronously()
        }
    }

    private func restoreHighResolutionWheelSynchronously() {
        guard !isRemoved,
              let controller = logitechHighResolutionWheelController else {
            clearHighResolutionWheelCache()
            invalidateLogitechHighResolutionWheelController()
            return
        }

        highResolutionWheelLock.lock()
        let initialEnabled = initialHighResolutionWheelEnabled
        highResolutionWheelLock.unlock()

        if let initialEnabled {
            _ = controller.setHighResolutionWheelEnabled(initialEnabled)
        }

        invalidateLogitechHighResolutionWheelController()
        clearHighResolutionWheelCache()
    }

    private func clearHighResolutionWheelCache() {
        highResolutionWheelLock.lock()
        cachedHighResolutionWheelEnabled = nil
        cachedHighResolutionWheelMultiplier = nil
        initialHighResolutionWheelEnabled = nil
        highResolutionWheelLock.unlock()
    }

    private func nextHighResolutionWheelApplyRequestID() -> UUID {
        highResolutionWheelLock.lock()
        defer { highResolutionWheelLock.unlock() }

        let requestID = UUID()
        highResolutionWheelApplyRequestID = requestID
        return requestID
    }

    private func cancelHighResolutionWheelApplyRequests() {
        highResolutionWheelLock.lock()
        highResolutionWheelApplyRequestID = UUID()
        highResolutionWheelLock.unlock()
    }

    private func isCurrentHighResolutionWheelApplyRequest(_ requestID: UUID) -> Bool {
        highResolutionWheelLock.lock()
        defer { highResolutionWheelLock.unlock() }

        return highResolutionWheelApplyRequestID == requestID
    }

    private func updateHighResolutionWheelCache(enabled: Bool?, multiplier: Int?) {
        highResolutionWheelLock.lock()
        cachedHighResolutionWheelEnabled = enabled
        cachedHighResolutionWheelMultiplier = enabled == true ? multiplier : nil
        highResolutionWheelLock.unlock()
    }
}
