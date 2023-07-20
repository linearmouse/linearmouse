// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Defaults
import Foundation
import os.log
import PointerKit

class Device {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Device")

    static let fallbackPointerAcceleration = 0.6875
    static let fallbackPointerResolution = 400.0
    static let fallbackPointerSpeed = pointerSpeed(fromPointerResolution: fallbackPointerResolution)

    private weak var manager: DeviceManager?
    private let device: PointerDevice

    private var removed = false

    @Default(.verbosedLoggingOn) private var verbosedLoggingOn

    private let initialPointerResolution: Double

    private var inputObservationToken: ObservationToken?

    init(_ manager: DeviceManager, _ device: PointerDevice) {
        self.manager = manager
        self.device = device

        initialPointerResolution = device.pointerResolution ?? Self.fallbackPointerResolution

        // TODO: More elegant way?
        inputObservationToken = device.observeInput(using: { [weak self] in
            self?.inputValueCallback($0, $1)
        })

        os_log("Device initialized: %{public}@: HIDPointerResolution=%{public}f, HIDPointerAccelerationType=%{public}@",
               log: Self.log, type: .info,
               String(describing: device),
               initialPointerResolution,
               device.pointerAccelerationType ?? "(unknown)")
    }

    func markRemoved() {
        removed = true
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
                   log: Self.log, type: .info,
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
                   log: Self.log, type: .info,
                   String(describing: self), newValue)
            device.pointerResolution = Self.pointerResolution(fromPointerSpeed: newValue)
        }
    }

    func restorePointerAcceleration() {
        let systemPointerAcceleration = (DeviceManager.shared
            .getSystemProperty(forKey: device.pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey) as IOFixed?)
            .map { Double($0) / 65536 } ?? Self.fallbackPointerAcceleration

        os_log("Restore pointer acceleration for device: %{public}@: %{public}f",
               log: Self.log, type: .info,
               String(describing: device),
               systemPointerAcceleration)

        pointerAcceleration = systemPointerAcceleration
    }

    func restorePointerSpeed() {
        os_log("Restore pointer speed for device: %{public}@: %{public}f",
               log: Self.log, type: .info,
               String(describing: device),
               Self.pointerSpeed(fromPointerResolution: initialPointerResolution))

        device.pointerResolution = initialPointerResolution
    }

    func restorePointerAccelerationAndPointerSpeed() {
        restorePointerSpeed()
        restorePointerAcceleration()
    }

    private func inputValueCallback(_ device: PointerDevice, _ value: IOHIDValue) {
        guard !removed else {
            os_log("Received input from removed device: %{public}@", log: Self.log, type: .error,
                   String(describing: device))
            os_log("Cancelling input observation for removed device: %{public}@", log: Self.log, type: .error,
                   String(describing: device))
            inputObservationToken = nil
            return
        }

        if verbosedLoggingOn {
            os_log("Received input value from: %{public}@: %{public}@", log: Self.log, type: .info,
                   String(describing: device), String(describing: value))
        }

        guard let manager = manager else {
            os_log("manager is nil", log: Self.log, type: .error)
            return
        }

        guard manager.lastActiveDeviceRef?.value != self else {
            return
        }

        let element = value.element

        let usagePage = element.usagePage
        let usage = element.usage

        switch Int(usagePage) {
        case kHIDPage_GenericDesktop:
            switch Int(usage) {
            case kHIDUsage_GD_X, kHIDUsage_GD_Y, kHIDUsage_GD_Z:
                guard IOHIDValueGetIntegerValue(value) != 0 else {
                    return
                }
            default:
                return
            }
        case kHIDPage_Button:
            break
        default:
            return
        }

        manager.lastActiveDeviceRef = .init(self)

        os_log("""
               Last active device changed: %{public}@, category=%{public}@ \
               (Reason: Received input value: usagePage=0x%{public}02X, usage=0x%{public}02X)
               """,
               log: Self.log, type: .info,
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
