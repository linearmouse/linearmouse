// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

protocol LogitechDeviceSettingsTarget: AnyObject {
    var isRemoved: Bool { get }
    var isLogitechSensorDPIApplyRunning: Bool { get }
    var isLogitechHighResolutionWheelApplyRunning: Bool { get }
    func hasConfirmedLogitechSensorDPI(_ dpi: Int) -> Bool
    var confirmedLogitechHighResolutionWheel: Bool? { get }
    var needsLogitechSensorDPIRestoreRetry: Bool { get }
    var needsLogitechHighResolutionWheelRestoreRetry: Bool { get }

    func applyConfiguredSensorDPI(_ dpi: Int)
    func applyConfiguredHighResolutionWheel(_ enabled: Bool)
    func requestLogitechControlsForcedReconfiguration()
    func prepareSensorDPIForReconnect()
    func prepareHighResolutionWheelForReconnect()
    func stopManagingSensorDPI()
    func stopManagingHighResolutionWheel()
}

extension Device: LogitechDeviceSettingsTarget {}

/// Applies the desired state for Logitech HID++ features and replays volatile
/// settings after a wake, reconnect, or connection switch.
final class LogitechDeviceSettingsReconciler {
    private weak var device: LogitechDeviceSettingsTarget?
    private let lock = NSLock()
    private var desiredScheme = Scheme()

    init(device: LogitechDeviceSettingsTarget) {
        self.device = device
    }

    func apply(_ scheme: Scheme) {
        apply(scheme, force: false)
    }

    func reapply(_ scheme: Scheme) {
        guard let device, !device.isRemoved else {
            return
        }

        device.prepareSensorDPIForReconnect()
        if scheme.logitech.highResolutionWheel != nil {
            device.prepareHighResolutionWheelForReconnect()
        }
        apply(scheme, force: true)
        device.requestLogitechControlsForcedReconfiguration()
    }

    /// Verifies volatile settings after a system wake without discarding the
    /// suspension's provisional Hi-Res multiplier. The session already
    /// invalidated feature transports and confirmed values before sleep.
    func reapplyAfterWake(_ scheme: Scheme) {
        guard let device, !device.isRemoved else {
            return
        }

        apply(scheme, force: true)
        device.requestLogitechControlsForcedReconfiguration()
    }

    private func apply(_ scheme: Scheme, force: Bool) {
        guard let device, !device.isRemoved else {
            return
        }

        let diff = lock.withLock { () -> SchemeDiff in
            let diff = SchemeDiff(previous: desiredScheme, current: scheme)
            desiredScheme = diff.current
            return diff
        }

        let dpiChanged = diff.changed(\.pointer.hardwareDPI)
        let wheelChanged = diff.changed(\.logitech.highResolutionWheel)

        // The scheme snapshot records only the request. The feature caches are
        // updated from HID++ reads/writes, and become nil after an exhausted
        // retry budget, so an unchanged configuration can converge again.
        if let dpi = scheme.pointer.hardwareDPI,
           force || dpiChanged ||
           (!device.isLogitechSensorDPIApplyRunning && !device.hasConfirmedLogitechSensorDPI(dpi)) {
            device.applyConfiguredSensorDPI(dpi)
        } else if scheme.pointer.hardwareDPI == nil,
                  force || dpiChanged
                  || device.needsLogitechSensorDPIRestoreRetry {
            device.stopManagingSensorDPI()
        }
        if let highResolutionWheel = scheme.logitech.highResolutionWheel,
           force || wheelChanged
           || (!device.isLogitechHighResolutionWheelApplyRunning
               && device.confirmedLogitechHighResolutionWheel != highResolutionWheel) {
            device.applyConfiguredHighResolutionWheel(highResolutionWheel)
        } else if scheme.logitech.highResolutionWheel == nil,
                  force || wheelChanged
                  || device.needsLogitechHighResolutionWheelRestoreRetry {
            device.stopManagingHighResolutionWheel()
        }
    }
}
