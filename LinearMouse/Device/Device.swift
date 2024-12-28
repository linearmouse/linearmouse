// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Defaults
import Foundation
import ObservationToken
import os.log
import PointerKit

class Device {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Device")

    static let fallbackPointerAcceleration = 0.6875
    static let fallbackPointerResolution = 400.0
    static let fallbackPointerSpeed = pointerSpeed(fromPointerResolution: fallbackPointerResolution)

    private struct Product: Hashable {
        let vendorID: Int
        let productID: Int
    }

    private static let productsToApplySideButtonFixes: Set<Product> = [
        .init(vendorID: 0x2717, productID: 0x5014), // Mi Silent Mouse
        .init(vendorID: 0x248A, productID: 0x8266), // Delux M729DB mouse
        .init(vendorID: 0x047d, productID: 0x2041)  // Kensington Slimblade
    ]

    private weak var manager: DeviceManager?
    private let device: PointerDevice

    private var removed = false

    @Default(.verbosedLoggingOn) private var verbosedLoggingOn

    private let initialPointerResolution: Double

    private var inputObservationToken: ObservationToken?
    private var reportObservationToken: ObservationToken?

    private var lastButtonStates: UInt8 = 0

    init(_ manager: DeviceManager, _ device: PointerDevice) {
        self.manager = manager
        self.device = device

        initialPointerResolution = device.pointerResolution ?? Self.fallbackPointerResolution

        // TODO: More elegant way?
        inputObservationToken = device.observeInput(using: { [weak self] in
            self?.inputValueCallback($0, $1)
        })

        // Some bluetooth devices, such as Mi Dual Mode Wireless Mouse Silent Edition, report only
        // 3 buttons in the HID report descriptor. As a result, macOS does not recognize side button
        // clicks from these devices.
        //
        // To work around this issue, we subscribe to the input reports and monitor the side button
        // states. When the side buttons are clicked, we simulate those events.
        if let vendorID = vendorID, let productID = productID {
            if (buttonCount == 3 && Self.productsToApplySideButtonFixes.contains(.init(vendorID: vendorID, productID: productID))) ||
               (vendorID == 0x047d && productID == 0x2041) { // Slimblade needs report monitoring regardless of button count
                reportObservationToken = device.observeReport(using: { [weak self] in
                    self?.inputReportCallback($0, $1)
                })
            }
        }

        os_log("Device initialized: %{public}@: HIDPointerResolution=%{public}f, HIDPointerAccelerationType=%{public}@",
               log: Self.log, type: .info,
               String(describing: device),
               initialPointerResolution,
               device.pointerAccelerationType ?? "(unknown)")
    }

    func markRemoved() {
        removed = true

        inputObservationToken = nil
        reportObservationToken = nil
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

    /**
     This feature was introduced in macOS Sonoma. In the earlier versions of
     macOS, this value would be nil.
     */
    var disablePointerAcceleration: Bool? {
        get {
            device.useLinearScalingMouseAcceleration.map { $0 != 0 }
        }
        set {
            guard device.useLinearScalingMouseAcceleration != nil, let newValue = newValue else {
                return
            }
            device.useLinearScalingMouseAcceleration = newValue ? 1 : 0
        }
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
        (1 / pointerResolution).normalized(from: pointerSpeedRange)
    }

    static func pointerResolution(fromPointerSpeed pointerSpeed: Double) -> Double {
        1 / (pointerSpeed.normalized(to: pointerSpeedRange))
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

    private func inputReportCallback(_ device: PointerDevice, _ report: Data) {
        if verbosedLoggingOn {
            let reportHex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
            os_log("Received input report from: %{public}@: %{public}@", log: Self.log, type: .info,
                   String(describing: device), String(describing: reportHex))
        }

        // FIXME: Correct HID Report parsing?
        guard report.count >= 2 else {
            return
        }
        if let vendorID = device.vendorID, let productID = device.productID {
            switch (vendorID, productID) {
            case (0x047d, 0x2041): // Slimblade
                // For Slimblade, byte 4 contains the vendor-defined button states
                let buttonStates = report[4]
                let toggled = lastButtonStates ^ buttonStates
                
                guard toggled != 0 else {
                    return
                }

                let topLeftMask: UInt8 = 0x1
                let topRightMask: UInt8 = 0x2

                // Check top left button
                if toggled & topLeftMask != 0 {
                    let down = buttonStates & topLeftMask != 0
                    simulateButtonEvent(button: 3, down: down, device: device)
                }

                // Check top right button
                if toggled & topRightMask != 0 {
                    let down = buttonStates & topRightMask != 0
                    simulateButtonEvent(button: 4, down: down, device: device)
                }

                lastButtonStates = buttonStates
                
            default: // Other devices with side button fixes
            // | Button 0 (1 bit) | ... | Button 4 (1 bit) | Not Used (3 bits) |
            let buttonStates = report[1] & 0x18
            let toggled = lastButtonStates ^ buttonStates
            guard toggled != 0 else {
                return
            }
            for button in 3 ... 4 {
                guard toggled & (1 << button) != 0 else {
                    continue
                }
                let down = buttonStates & (1 << button) != 0
                simulateButtonEvent(button: button, down: down, device: device)
            }
            lastButtonStates = buttonStates
        }
        }
    }

    private func simulateButtonEvent(button: Int, down: Bool, device: PointerDevice) {
        os_log("Simulate button %{public}d %{public}@ event for device: %{public}@",
               log: Self.log,
               type: .info,
               button,
               down ? "down" : "up",
               String(describing: device))
               
        guard let location = CGEvent(source: nil)?.location else { return }
        guard let event = CGEvent(mouseEventSource: nil,
                                mouseType: down ? .otherMouseDown : .otherMouseUp,
                                mouseCursorPosition: location,
                                mouseButton: CGMouseButton(rawValue: UInt32(button))!) else { return }
                                
        event.post(tap: .cghidEventTap)
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
