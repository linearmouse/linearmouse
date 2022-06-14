//
//  Device.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/14.
//

import Foundation
import os.log
import PointerKit

class Device {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Device")

    private static let fallbackPointerAcceleration = 0.6875

    private weak var manager: DeviceManager?
    let device: PointerDevice

    private let initialPointerResolution: Double

    init?(_ manager: DeviceManager, _ device: PointerDevice) {
        self.manager = manager
        self.device = device

        guard let pointerResolution = device.pointerResolution else {
            os_log("HIDPointerResolution not found: %{public}@",
                   log: Self.log, type: .debug,
                   String(describing: device))
            return nil
        }
        self.initialPointerResolution = pointerResolution

        device.observeInput(using: inputCallback).tieToLifetime(of: self)

        os_log("Device initialized: %{public}@: HIDPointerResolution=%{public}f, HIDPointerAccelerationType=%{public}@",
               log: Self.log, type: .debug,
               String(describing: device),
               pointerResolution,
               device.pointerAccelerationType ?? "(unknown)")
    }

    enum Category {
        case mouse, trackpad
    }

    private func isAppleMagicMouse(vendorID: Int, productID: Int) -> Bool {
        [0x004C, 0x05AC].contains(vendorID) && [0x0269, 0x030D].contains(productID)
    }

    lazy var category: Category = {
        if let vendorID: Int = device.vendorID,
           let productID: Int = device.productID {
            if isAppleMagicMouse(vendorID: vendorID, productID: productID) {
                return .mouse
            }
        }
        if device.confirmsTo(kHIDPage_Digitizer, kHIDUsage_Dig_TouchPad) {
            return .trackpad
        }
        return .mouse
    }()

    var pointerAcceleration: Double {
        device.pointerAcceleration ?? Self.fallbackPointerAcceleration
    }

    var pointerSensitivity: Double {
        device.pointerResolution.map { 2000 - $0 } ?? 1600
    }

    var shouldApplyPointerSpeedSettings: Bool {
        guard category == .mouse else {
            os_log("Device ignored for pointer speed settings: %@: Category is %@",
                   log: Self.log, type: .debug,
                   String(describing: self), String(describing: category))
            return false
        }
        return true
    }

    func updatePointerSpeed(acceleration: Double, sensitivity: Double, disableAcceleration: Bool) {
        guard shouldApplyPointerSpeedSettings else {
            return
        }

        if disableAcceleration {
            os_log("Disable acceleration and sensitivity for device: %{public}@",
                   log: Self.log, type: .debug,
                   String(describing: device))
            device.pointerAcceleration = -1
        } else {
            os_log("Update speed for device: %{public}@, acceleration = %{public}f, sensitivity = %{public}f",
                   log: Self.log, type: .debug,
                   String(describing: device),
                   acceleration,
                   sensitivity)
            device.pointerAcceleration = acceleration
            device.pointerResolution = 2000 - sensitivity
        }
    }

    func restorePointerSpeedToInitialValue() {
        guard shouldApplyPointerSpeedSettings else {
            return
        }

        let systemPointerAcceleration = (DeviceManager.shared.getSystemProperty(forKey: device.pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey) as IOFixed?)
            .map { Double($0) / 65536 } ?? Self.fallbackPointerAcceleration

        os_log("Revert speed for device: %{public}@, acceleration = %{public}f, sensitivity = %{public}f",
               log: Self.log, type: .debug,
               String(describing: device),
               systemPointerAcceleration,
               initialPointerResolution)

        device.pointerResolution = initialPointerResolution
        device.pointerAcceleration = systemPointerAcceleration
    }

    private func inputCallback(device: PointerDevice, value: IOHIDValue) {
        guard let manager = manager else {
            return
        }

        if let lastActiveDevice = manager._lastActiveDevice {
            if lastActiveDevice == self {
                return
            }
        }

        manager._lastActiveDevice = self

        os_log("Last active device changed: %{public}@, Category=%{public}@",
               log: Self.log, type: .debug,
               String(describing: device), String(describing: category))
    }
}

extension Device: Hashable {
    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.device == rhs.device
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(device)
    }
}

extension Device: CustomStringConvertible {
    var description: String {
        device.description
    }
}
