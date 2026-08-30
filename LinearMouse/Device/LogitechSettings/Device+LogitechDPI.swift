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
        logitechSession.renewDPITransport()
        logitechSession.dpiApplyCoordinator.start { [weak self] attempt in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let start = Date()
            let appliedDPI = applySensorDPISynchronously(
                dpi,
                verifiesCachedValue: attempt.verifiesCachedValue
            )
            guard !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let phase = attempt.verifiesCachedValue ? "verification" : "apply"
            let duration = Date().timeIntervalSince(start)
            let slot = logitechReceiverRouteSnapshot.map { String($0.slot) } ?? "direct"
            if let appliedDPI {
                os_log(
                    "Logitech hardware DPI %{public}@ succeeded: dpi=%{public}d device=%{public}@ slot=%{public}@ attempt=%{public}d duration=%{public}.3f",
                    log: Self.logitechDPILog,
                    type: .info,
                    phase,
                    appliedDPI,
                    name,
                    slot,
                    attempt.number,
                    duration
                )
                return true
            }

            os_log(
                "Logitech hardware DPI %{public}@ attempt failed: dpi=%{public}d device=%{public}@ slot=%{public}@ attempt=%{public}d final=%{public}@ duration=%{public}.3f",
                log: Self.logitechDPILog,
                type: attempt.isFinal ? .error : .info,
                phase,
                dpi,
                name,
                slot,
                attempt.number,
                attempt.isFinal ? "true" : "false",
                duration
            )
            return false
        }
    }

    func refreshHardwareDPIInfo(completion: @escaping (HardwareDPIInfo) -> Void) {
        logitechSession.queue.async {
            let info = self.hardwareDPIInfo

            DispatchQueue.main.async {
                completion(info)
            }
        }
    }

    func applyHardwareDPI(_ dpi: Int, completion: @escaping (HardwareDPIApplyResult) -> Void) {
        logitechSession.dpiApplyCoordinator.cancel()
        logitechSession.renewDPITransport()
        logitechSession.queue.async {
            let result: HardwareDPIApplyResult
            if !self.isRemoved, let controller = self.logitechAdjustableDPI {
                let targetDPI = self.applySensorDPISynchronously(dpi, controller: controller)
                let currentDPI = self.logitechSession.withState { targetDPI ?? $0.sensorDPI }
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
            logitechSession.withState { $0.sensorDPI = currentDPI }
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

        let cachedDPI = logitechSession.withState { $0.sensorDPI }

        if cachedDPI == targetDPI {
            if !verifiesCachedValue || controller.currentDPI() == targetDPI {
                return targetDPI
            }
        }

        guard let appliedDPI = controller.setDPI(targetDPI) else {
            return nil
        }

        logitechSession.withState { $0.sensorDPI = appliedDPI }

        return appliedDPI
    }

    func restoreSensorDPI() {
        logitechSession.dpiApplyCoordinator.cancel()
        logitechSession.renewDPITransport()
        logitechSession.withState { $0.sensorDPI = nil }
    }

    func prepareSensorDPIForReconnect() {
        logitechSession.dpiApplyCoordinator.cancel()
        logitechSession.renewDPITransport()
        logitechSession.withState { $0.sensorDPI = nil }
    }
}
