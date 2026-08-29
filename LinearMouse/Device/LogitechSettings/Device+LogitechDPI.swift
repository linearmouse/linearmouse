// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import os.log

extension Device {
    private static let logitechDPILog = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HardwareDPI"
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

    func applyConfiguredSensorDPI(_ dpi: Int) {
        dpiApplyCoordinator.start { [weak self] verifiesCachedValue in
            guard let self, !isRemoved else {
                return false
            }

            let appliedDPI = applySensorDPISynchronously(
                dpi,
                verifiesCachedValue: verifiesCachedValue
            )
            if appliedDPI == nil {
                os_log(
                    "Failed to apply configured hardware DPI %{public}d to %{public}@",
                    log: Self.logitechDPILog,
                    type: .error,
                    dpi,
                    name
                )
            }
            return appliedDPI != nil
        }
    }

    func refreshHardwareDPIInfo(completion: @escaping (HardwareDPIInfo) -> Void) {
        logitechSettingsQueue.async {
            let info = self.hardwareDPIInfo

            DispatchQueue.main.async {
                completion(info)
            }
        }
    }

    func applyHardwareDPI(_ dpi: Int, completion: @escaping (HardwareDPIApplyResult) -> Void) {
        dpiApplyCoordinator.cancel()
        logitechSettingsQueue.async {
            let result: HardwareDPIApplyResult
            if !self.isRemoved, let controller = self.logitechAdjustableDPI {
                let targetDPI = self.applySensorDPISynchronously(dpi, controller: controller)
                self.logitechSettingsLock.lock()
                let currentDPI = targetDPI ?? self.cachedSensorDPI
                self.logitechSettingsLock.unlock()
                result = HardwareDPIApplyResult(
                    targetDPI: targetDPI,
                    info: HardwareDPIInfo(
                        supportsAdjustableDPI: true,
                        currentDPI: currentDPI,
                        dpiRange: controller.dpiRange
                    )
                )
            } else {
                result = HardwareDPIApplyResult(
                    targetDPI: nil,
                    info: self.unsupportedHardwareDPIInfo
                )
            }

            DispatchQueue.main.async {
                completion(result)
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
        guard !isRemoved, let controller = logitechAdjustableDPI else {
            return unsupportedHardwareDPIInfo
        }

        let currentDPI = controller.currentDPI()
        if let currentDPI {
            logitechSettingsLock.lock()
            cachedSensorDPI = currentDPI
            logitechSettingsLock.unlock()
        }

        return HardwareDPIInfo(
            supportsAdjustableDPI: true,
            currentDPI: currentDPI,
            dpiRange: controller.dpiRange
        )
    }

    private func applySensorDPISynchronously(
        _ dpi: Int,
        verifiesCachedValue: Bool = false
    ) -> Int? {
        guard !isRemoved,
              let controller = logitechAdjustableDPI else {
            return nil
        }

        return applySensorDPISynchronously(
            dpi,
            controller: controller,
            verifiesCachedValue: verifiesCachedValue
        )
    }

    private func applySensorDPISynchronously(
        _ dpi: Int,
        controller: AdjustableDPI,
        verifiesCachedValue: Bool = false
    ) -> Int? {
        let targetDPI = controller.supportedDPI(nearestTo: dpi)
        guard controller.canRepresentDPI(targetDPI) else {
            return nil
        }

        logitechSettingsLock.lock()
        let cachedDPI = cachedSensorDPI
        logitechSettingsLock.unlock()

        if cachedDPI == targetDPI {
            if !verifiesCachedValue || controller.currentDPI() == targetDPI {
                return targetDPI
            }
        }

        guard let appliedDPI = controller.setDPI(targetDPI) else {
            return nil
        }

        logitechSettingsLock.lock()
        cachedSensorDPI = appliedDPI
        logitechSettingsLock.unlock()

        return appliedDPI
    }

    func restoreSensorDPI() {
        dpiApplyCoordinator.cancel()
        logitechSettingsLock.lock()
        cachedSensorDPI = nil
        logitechSettingsLock.unlock()
    }

    func prepareSensorDPIForReconnect() {
        dpiApplyCoordinator.cancel()
        logitechSettingsQueue.async { [weak self] in
            guard let self else {
                return
            }

            logitechSettingsLock.lock()
            cachedSensorDPI = nil
            logitechSettingsLock.unlock()
            invalidateLogitechAdjustableDPI()
        }
    }
}
