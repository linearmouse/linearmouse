// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log
import PointerKit

class Device {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Device")

    static let fallbackPointerAcceleration = 0.6875
    static let fallbackPointerResolution = 400.0
    static let fallbackPointerSpeed = pointerSpeed(fromPointerResolution: fallbackPointerResolution)

    private weak var manager: DeviceManager?
    let device: PointerDevice

    private let initialPointerResolution: Double

    init(_ manager: DeviceManager, _ device: PointerDevice) {
        self.manager = manager
        self.device = device

        initialPointerResolution = device.pointerResolution ?? Self.fallbackPointerResolution

        // TODO: More elegant way?
        device.observeInput(using: { [weak self] in
            self?.inputValueCallback($0, $1)
        }).tieToLifetime(of: self)

        os_log("Device initialized: %{public}@: HIDPointerResolution=%{public}f, HIDPointerAccelerationType=%{public}@",
               log: Self.log, type: .debug,
               String(describing: device),
               initialPointerResolution,
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

    var buttonCount: Int? {
        device.buttonCount
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
            os_log("Update pointer acceleration for device: %{public}@: %{public}f",
                   log: Self.log, type: .debug,
                   String(describing: self), newValue)
            device.pointerAcceleration = newValue
        }
    }

    private static let pointerSpeedRange = 1.0 / 1200 ... 1.0 / 40

    static func pointerSpeed(fromPointerResolution pointerResolution: Double) -> Double {
        (1 / pointerResolution).normalized(from: Self.pointerSpeedRange)
    }

    static func pointerResolution(fromPointerSpeed pointerSpeed: Double) -> Double {
        1 / (pointerSpeed.normalized(to: Self.pointerSpeedRange))
    }

    var pointerSpeed: Double {
        get {
            device.pointerResolution.map { Self.pointerSpeed(fromPointerResolution: $0) } ?? Self
                .fallbackPointerSpeed
        }
        set {
            os_log("Update pointer speed for device: %{public}@: %{public}f",
                   log: Self.log, type: .debug,
                   String(describing: self), newValue)
            device.pointerResolution = Self.pointerResolution(fromPointerSpeed: newValue)
        }
    }

    func restorePointerAcceleration() {
        let systemPointerAcceleration = (DeviceManager.shared
            .getSystemProperty(forKey: device.pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey) as IOFixed?)
            .map { Double($0) / 65536 } ?? Self.fallbackPointerAcceleration

        os_log("Restore pointer acceleration for device: %{public}@: %{public}f",
               log: Self.log, type: .debug,
               String(describing: device),
               systemPointerAcceleration)

        pointerAcceleration = systemPointerAcceleration
    }

    func restorePointerSpeed() {
        os_log("Restore pointer speed for device: %{public}@: %{public}f",
               log: Self.log, type: .debug,
               String(describing: device),
               Self.pointerSpeed(fromPointerResolution: initialPointerResolution))

        device.pointerResolution = initialPointerResolution
    }

    func restorePointerAccelerationAndPointerSpeed() {
        restorePointerSpeed()
        restorePointerAcceleration()
    }

    private func inputValueCallback(_ device: PointerDevice, _ value: IOHIDValue) {
        guard let manager = manager else {
            return
        }

        guard manager.lastActiveDevice != self || manager.lastActiveDeviceIncludingMovements != self else {
            return
        }

        let element = IOHIDValueGetElement(value)

        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == kHIDPage_GenericDesktop || usagePage == kHIDPage_Digitizer || usagePage == kHIDPage_Button
        else {
            return
        }

        if usagePage == kHIDPage_GenericDesktop {
            if usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y || usage == kHIDUsage_GD_Z {
                guard IOHIDValueGetIntegerValue(value) != 0 else {
                    return
                }
            }
        }

        if usagePage == kHIDPage_GenericDesktop || usagePage == kHIDPage_Digitizer {
            if manager.lastActiveDeviceIncludingMovements != self {
                manager.lastActiveDeviceIncludingMovements = self
            }

            return
        }

        if manager.lastActiveDevice != self {
            manager.lastActiveDevice = self
        }

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
