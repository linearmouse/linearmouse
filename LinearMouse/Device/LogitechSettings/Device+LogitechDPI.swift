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
        enum Outcome: Equatable {
            case applied
            case unsupported
            case cancelled
        }

        let targetDPI: Int?
        let info: HardwareDPIInfo
        let outcome: Outcome

        init(
            targetDPI: Int?,
            info: HardwareDPIInfo,
            outcome: Outcome = .applied
        ) {
            self.targetDPI = targetDPI
            self.info = info
            self.outcome = outcome
        }
    }

    var confirmedLogitechSensorDPI: Int? {
        logitechSession.sensorDPI
    }

    func applyConfiguredSensorDPI(_ dpi: Int) {
        logitechSession.startDPIApply { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let start = Date()
            let appliedDPI = applySensorDPISynchronously(
                dpi,
                expectedToken: token,
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
        logitechSession.perform {
            let info = self.hardwareDPIInfo

            DispatchQueue.main.async {
                completion(info)
            }
        }
    }

    func applyHardwareDPI(_ dpi: Int, completion: @escaping (HardwareDPIApplyResult) -> Void) {
        let cancelledResult = {
            HardwareDPIApplyResult(
                targetDPI: nil,
                info: self.unsupportedHardwareDPIInfo,
                outcome: .cancelled
            )
        }
        let deliver: (HardwareDPIApplyResult, CancellationToken?) -> Void = { result, token in
            DispatchQueue.main.async {
                guard token?.shouldContinue != false, !self.isRemoved else {
                    completion(cancelledResult())
                    return
                }
                completion(result)
            }
        }

        logitechSession.runDPIOperation { token in
            let result: HardwareDPIApplyResult
            if !self.isRemoved, let access = self.logitechAdjustableDPI(for: token) {
                let targetDPI = self.applySensorDPISynchronously(dpi, access: access)
                let currentDPI = targetDPI ?? self.logitechSession.sensorDPI
                result = HardwareDPIApplyResult(
                    targetDPI: targetDPI,
                    info: HardwareDPIInfo(
                        supportsAdjustableDPI: true,
                        currentDPI: currentDPI,
                        dpiRange: access.feature.dpiRange
                    ),
                    outcome: .applied
                )
            } else {
                result = HardwareDPIApplyResult(
                    targetDPI: nil,
                    info: self.unsupportedHardwareDPIInfo,
                    outcome: token.shouldContinue ? .unsupported : .cancelled
                )
            }
            deliver(result, token)
        } onCancelled: {
            deliver(cancelledResult(), nil)
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
        guard !isRemoved, let access = logitechAdjustableDPI else {
            return unsupportedHardwareDPIInfo
        }

        let controller = access.feature
        let currentDPI = controller.currentDPI()
        if let currentDPI {
            logitechSession.updateSensorDPI(currentDPI, for: access)
        }

        return HardwareDPIInfo(
            supportsAdjustableDPI: true,
            currentDPI: currentDPI,
            dpiRange: controller.dpiRange
        )
    }

    private func applySensorDPISynchronously(
        _ dpi: Int,
        expectedToken: CancellationToken,
        verifiesCachedValue: Bool = false
    ) -> Int? {
        guard !isRemoved,
              let access = logitechAdjustableDPI(for: expectedToken) else {
            return nil
        }

        return applySensorDPISynchronously(
            dpi,
            access: access,
            verifiesCachedValue: verifiesCachedValue
        )
    }

    private func applySensorDPISynchronously(
        _ dpi: Int,
        access: LogitechDeviceSession.FeatureAccess<AdjustableDPI>,
        verifiesCachedValue: Bool = false
    ) -> Int? {
        let controller = access.feature
        let targetDPI = controller.supportedDPI(nearestTo: dpi)
        guard controller.canRepresentDPI(targetDPI) else {
            return nil
        }

        let cachedDPI = logitechSession.sensorDPI

        if cachedDPI == targetDPI {
            if !verifiesCachedValue || controller.currentDPI() == targetDPI {
                return targetDPI
            }
        }

        guard let appliedDPI = controller.setDPI(targetDPI) else {
            return nil
        }

        logitechSession.updateSensorDPI(appliedDPI, for: access)

        return appliedDPI
    }

    func restoreSensorDPI() {
        logitechSession.cancelDPIApply()
        logitechSession.clearSensorDPI()
    }

    func prepareSensorDPIForReconnect() {
        logitechSession.cancelDPIApply()
        logitechSession.clearSensorDPI()
    }
}
