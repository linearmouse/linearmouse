// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log
import PointerKit

class Device {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Device")

    static let fallbackPointerAcceleration = 0.6875
    static let fallbackPointerSpeed = pointerSensitivity(fromPointerResolution: 400)

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
        initialPointerResolution = pointerResolution

        device.observeInput(using: inputValueCallback).tieToLifetime(of: self)

        os_log("Device initialized: %{public}@: HIDPointerResolution=%{public}f, HIDPointerAccelerationType=%{public}@",
               log: Self.log, type: .debug,
               String(describing: device),
               pointerResolution,
               device.pointerAccelerationType ?? "(unknown)")
    }
}

extension Device {
    var name: String {
        device.name
    }

    var productName: String? {
        device.product
    }

    var vendorID: Int? {
        device.vendorID
    }

    var productID: Int? {
        device.productID
    }

    var serialNumber: String? {
        device.serialNumber
    }

    enum Category {
        case mouse, trackpad
    }

    private func isAppleMagicMouse(vendorID: Int, productID: Int) -> Bool {
        [0x004C, 0x05AC].contains(vendorID) && [0x0269, 0x030D].contains(productID)
    }

    var category: Category {
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
    }

    var pointerAcceleration: Double {
        get {
            device.pointerAcceleration ?? Self.fallbackPointerAcceleration
        }
        set {
            device.pointerAcceleration = newValue
        }
    }

    private static let pointerSensitivityRange = 1.0 / 1200 ... 1.0 / 40

    static func pointerSensitivity(fromPointerResolution pointerResolution: Double) -> Double {
        (1 / pointerResolution).normalized(from: Self.pointerSensitivityRange)
    }

    static func pointerResolution(fromPointerSensitivity pointerSensitivity: Double) -> Double {
        1 / (pointerSensitivity.normalized(to: Self.pointerSensitivityRange))
    }

    var pointerSensitivity: Double {
        get {
            device.pointerResolution.map { Self.pointerSensitivity(fromPointerResolution: $0) } ?? Self
                .fallbackPointerSpeed
        }
        set {
            device.pointerResolution = Self.pointerResolution(fromPointerSensitivity: newValue)
        }
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
            pointerAcceleration = acceleration
            pointerSensitivity = sensitivity
        }
    }

    func restorePointerSpeedToInitialValue() {
        guard shouldApplyPointerSpeedSettings else {
            return
        }

        let systemPointerAcceleration = (DeviceManager.shared
            .getSystemProperty(forKey: device.pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey) as IOFixed?)
            .map { Double($0) / 65536 } ?? Self.fallbackPointerAcceleration

        os_log("Revert speed for device: %{public}@, acceleration = %{public}f, sensitivity = %{public}f",
               log: Self.log, type: .debug,
               String(describing: device),
               systemPointerAcceleration,
               initialPointerResolution)

        device.pointerResolution = initialPointerResolution
        pointerAcceleration = systemPointerAcceleration
    }

    private func inputValueCallback(device: PointerDevice, value: IOHIDValue) {
        guard let manager = manager else {
            return
        }

        let element = IOHIDValueGetElement(value)

        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == kHIDPage_GenericDesktop || usagePage == kHIDPage_Digitizer || usagePage == kHIDPage_Button
        else {
            return
        }

        switch Int(usagePage) {
        case kHIDPage_GenericDesktop:
            switch Int(usage) {
            case kHIDUsage_GD_X, kHIDUsage_GD_Y, kHIDUsage_GD_Z, kHIDUsage_GD_Wheel:
                guard IOHIDValueGetIntegerValue(value) != 0 else {
                    return
                }
            default:
                break
            }
        default:
            break
        }

        if let lastActiveDevice = manager.lastActiveDevice {
            if lastActiveDevice == self {
                return
            }
        }

        manager.lastActiveDevice = self

        os_log("""
               Last active device changed: %{public}@, category=%{public}@ \
               (Reason: Received input value: usagePage=0x%{public}02X, usage=0x%{public}02X)
               """,
               log: Self.log, type: .debug,
               String(describing: device),
               String(describing: category),
               usagePage,
               usage)
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
