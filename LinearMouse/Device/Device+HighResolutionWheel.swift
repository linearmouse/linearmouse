// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Device {
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

        guard let retryDelay = LogitechDeviceConfigurationRetryPolicy.delay(afterAttempt: attempt) else {
            return
        }

        Self.highResolutionWheelQueue
            .asyncAfter(deadline: .now() + retryDelay) { [weak self] in
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

        highResolutionWheelLock.lock()
        if cachedHighResolutionWheelEnabled == enabled {
            highResolutionWheelLock.unlock()
            return enabled
        }
        highResolutionWheelLock.unlock()

        let capabilities = controller.capabilities()
        guard let result = controller.applyHighResolutionWheelEnabled(enabled) else {
            return nil
        }

        highResolutionWheelLock.lock()
        if initialHighResolutionWheelEnabled == nil {
            initialHighResolutionWheelEnabled = result.previousEnabled
        }
        highResolutionWheelLock.unlock()

        updateHighResolutionWheelCache(
            enabled: result.appliedEnabled,
            multiplier: result.appliedEnabled ? capabilities.map { Int($0.multiplier) } : nil
        )

        return result.appliedEnabled
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
        Self.highResolutionWheelQueue.async { [weak self] in
            self?.restoreHighResolutionWheelSynchronously()
        }
    }

    func prepareHighResolutionWheelForReconnect() {
        cancelHighResolutionWheelApplyRequests()
        Self.highResolutionWheelQueue.async { [weak self] in
            guard let self else {
                return
            }

            invalidateLogitechHighResolutionWheelController()
            highResolutionWheelLock.lock()
            cachedHighResolutionWheelEnabled = nil
            cachedHighResolutionWheelMultiplier = nil
            highResolutionWheelLock.unlock()
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
