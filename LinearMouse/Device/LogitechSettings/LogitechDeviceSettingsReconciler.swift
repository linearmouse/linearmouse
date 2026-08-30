// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

struct LogitechDeviceSettings: Equatable {
    var dpi: Int?
    var highResolutionWheel: Bool?
}

protocol LogitechDeviceSettingsTarget: AnyObject {
    var isRemoved: Bool { get }
    var confirmedLogitechSensorDPI: Int? { get }
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
    private var desiredSettings = LogitechDeviceSettings()

    init(device: LogitechDeviceSettingsTarget) {
        self.device = device
    }

    func apply(_ settings: LogitechDeviceSettings) {
        apply(settings, force: false)
    }

    func reapply(_ settings: LogitechDeviceSettings) {
        guard let device, !device.isRemoved else {
            return
        }

        device.prepareSensorDPIForReconnect()
        if settings.highResolutionWheel != nil {
            device.prepareHighResolutionWheelForReconnect()
        }
        apply(settings, force: true)
        device.requestLogitechControlsForcedReconfiguration()
    }

    /// Verifies volatile settings after a system wake without discarding the
    /// suspension's provisional Hi-Res multiplier. The session already
    /// invalidated feature transports and confirmed values before sleep.
    func reapplyAfterWake(_ settings: LogitechDeviceSettings) {
        guard let device, !device.isRemoved else {
            return
        }

        apply(settings, force: true)
        device.requestLogitechControlsForcedReconfiguration()
    }

    private func apply(_ settings: LogitechDeviceSettings, force: Bool) {
        guard let device, !device.isRemoved else {
            return
        }

        let previousSettings = lock.withLock { () -> LogitechDeviceSettings in
            let previous = desiredSettings
            desiredSettings = settings
            return previous
        }

        // desiredSettings records only the request. The feature caches are
        // updated from HID++ reads/writes, and become nil after an exhausted
        // retry budget, so an unchanged configuration can converge again.
        if let dpi = settings.dpi,
           force || dpi != previousSettings.dpi || device.confirmedLogitechSensorDPI != dpi {
            device.applyConfiguredSensorDPI(dpi)
        } else if settings.dpi == nil,
                  force || previousSettings.dpi != nil
                  || device.needsLogitechSensorDPIRestoreRetry {
            device.stopManagingSensorDPI()
        }
        if let highResolutionWheel = settings.highResolutionWheel,
           force || highResolutionWheel != previousSettings.highResolutionWheel
           || device.confirmedLogitechHighResolutionWheel != highResolutionWheel {
            device.applyConfiguredHighResolutionWheel(highResolutionWheel)
        } else if settings.highResolutionWheel == nil,
                  force || previousSettings.highResolutionWheel != nil
                  || device.needsLogitechHighResolutionWheelRestoreRetry {
            device.stopManagingHighResolutionWheel()
        }
    }
}
