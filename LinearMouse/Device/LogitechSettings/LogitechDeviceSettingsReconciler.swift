// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

struct LogitechDeviceSettings: Equatable {
    var dpi: Int?
    var highResolutionWheel: Bool?
}

protocol LogitechDeviceSettingsTarget: AnyObject {
    var isRemoved: Bool { get }

    func applyConfiguredSensorDPI(_ dpi: Int)
    func applyConfiguredHighResolutionWheel(_ enabled: Bool)
    func requestLogitechControlsForcedReconfiguration()
    func prepareSensorDPIForReconnect()
    func prepareHighResolutionWheelForReconnect()
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
        device.prepareHighResolutionWheelForReconnect()
        apply(settings, force: true)
        device.requestLogitechControlsForcedReconfiguration()
    }

    private func apply(_ settings: LogitechDeviceSettings, force: Bool) {
        guard let device, !device.isRemoved else {
            return
        }

        lock.lock()
        let previousSettings = desiredSettings
        desiredSettings = settings
        lock.unlock()

        if let dpi = settings.dpi, force || dpi != previousSettings.dpi {
            device.applyConfiguredSensorDPI(dpi)
        }
        if let highResolutionWheel = settings.highResolutionWheel,
           force || highResolutionWheel != previousSettings.highResolutionWheel {
            device.applyConfiguredHighResolutionWheel(highResolutionWheel)
        }
    }
}
