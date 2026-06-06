// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Device {
    private static let hardwareDPIQueue = DispatchQueue(
        label: "app.linearmouse.hardware-dpi",
        qos: .userInitiated
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
        Self.hardwareDPIQueue.async {
            _ = self.applyHardwareDPISynchronously(dpi)
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
        if cachedHardwareDPI == targetDPI {
            hardwareDPILock.unlock()
            return targetDPI
        }
        hardwareDPILock.unlock()

        guard let appliedDPI = controller.setDPI(targetDPI) else {
            return nil
        }

        hardwareDPILock.lock()
        cachedHardwareDPI = appliedDPI
        hardwareDPILock.unlock()

        return appliedDPI
    }

    func restoreHardwareDPI() {
        hardwareDPILock.lock()
        cachedHardwareDPI = nil
        hardwareDPILock.unlock()
    }
}
