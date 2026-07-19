// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Device {
    private enum HardwareDPIApplyRetry {
        static let maxAttempts = 8
        static let delay: TimeInterval = 5
    }

    private static let hardwareDPIQueue = DispatchQueue(
        label: "app.linearmouse.hardware-dpi",
        qos: .default
    )

    struct HardwareDPIInfo: Equatable {
        let supportsAdjustableDPI: Bool
        let currentDPI: Int?
        let dpiRange: ClosedRange<Int>?
    }

    struct HardwareDPIApplyResult: Equatable {
        let targetDPI: Int?
        let info: HardwareDPIInfo
    }

    func applyConfiguredHardwareDPI(_ dpi: Int) {
        let requestID = nextHardwareDPIApplyRequestID()
        Self.hardwareDPIQueue.async {
            self.applyConfiguredHardwareDPI(dpi, requestID: requestID, attempt: 1)
        }
    }

    private func applyConfiguredHardwareDPI(_ dpi: Int, requestID: UUID, attempt: Int) {
        guard isCurrentHardwareDPIApplyRequest(requestID), !isRemoved else {
            return
        }

        guard applyHardwareDPISynchronously(dpi) == nil else {
            return
        }

        guard attempt < HardwareDPIApplyRetry.maxAttempts else {
            return
        }

        Self.hardwareDPIQueue
            .asyncAfter(deadline: .now() + HardwareDPIApplyRetry.delay) { [weak self] in
                self?.applyConfiguredHardwareDPI(dpi, requestID: requestID, attempt: attempt + 1)
            }
    }

    func refreshHardwareDPIInfo(completion: @escaping (HardwareDPIInfo) -> Void) {
        Self.hardwareDPIQueue.async {
            let info = self.hardwareDPIInfo

            DispatchQueue.main.async {
                completion(info)
            }
        }
    }

    func applyHardwareDPI(_ dpi: Int, completion: @escaping (HardwareDPIApplyResult) -> Void) {
        cancelHardwareDPIApplyRequests()
        Self.hardwareDPIQueue.async {
            let targetDPI = self.applyHardwareDPISynchronously(dpi)
            let info = self.hardwareDPIInfo

            DispatchQueue.main.async {
                completion(HardwareDPIApplyResult(
                    targetDPI: targetDPI,
                    info: info
                ))
            }
        }
    }

    private var unsupportedHardwareDPIInfo: HardwareDPIInfo {
        HardwareDPIInfo(
            supportsAdjustableDPI: false,
            currentDPI: nil,
            dpiRange: nil
        )
    }

    private var hardwareDPIInfo: HardwareDPIInfo {
        guard !isRemoved, let controller = logitechDPIController else {
            return unsupportedHardwareDPIInfo
        }

        return HardwareDPIInfo(
            supportsAdjustableDPI: true,
            currentDPI: controller.currentDPI(),
            dpiRange: controller.dpiRange
        )
    }

    private func applyHardwareDPISynchronously(_ dpi: Int) -> Int? {
        guard !isRemoved,
              let controller = logitechDPIController else {
            return nil
        }

        let targetDPI = controller.supportedDPI(nearestTo: dpi)
        guard controller.canRepresentDPI(targetDPI) else {
            return nil
        }

        hardwareDPILock.lock()
        let cachedDPI = cachedHardwareDPI
        hardwareDPILock.unlock()

        if cachedDPI == targetDPI,
           controller.currentDPI() == targetDPI {
            return targetDPI
        }

        guard let appliedDPI = controller.setDPI(targetDPI) else {
            invalidateLogitechDPIController()
            return nil
        }

        hardwareDPILock.lock()
        cachedHardwareDPI = appliedDPI
        hardwareDPILock.unlock()

        return appliedDPI
    }

    func restoreHardwareDPI() {
        cancelHardwareDPIApplyRequests()
        hardwareDPILock.lock()
        cachedHardwareDPI = nil
        hardwareDPILock.unlock()
    }

    private func nextHardwareDPIApplyRequestID() -> UUID {
        hardwareDPILock.lock()
        defer { hardwareDPILock.unlock() }

        let requestID = UUID()
        hardwareDPIApplyRequestID = requestID
        return requestID
    }

    private func cancelHardwareDPIApplyRequests() {
        hardwareDPILock.lock()
        hardwareDPIApplyRequestID = UUID()
        hardwareDPILock.unlock()
    }

    private func isCurrentHardwareDPIApplyRequest(_ requestID: UUID) -> Bool {
        hardwareDPILock.lock()
        defer { hardwareDPILock.unlock() }

        return hardwareDPIApplyRequestID == requestID
    }
}
