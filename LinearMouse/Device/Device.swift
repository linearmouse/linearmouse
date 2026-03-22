// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Defaults
import Foundation
import ObservationToken
import os.log
import PointerKit

class Device {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!, category: "Device"
    )

    static let fallbackPointerAcceleration = 0.6875
    static let fallbackPointerResolution = 400.0
    static let fallbackPointerSpeed = pointerSpeed(
        fromPointerResolution: fallbackPointerResolution
    )

    private static var nextID: Int32 = 0

    private(set) lazy var id: Int32 = OSAtomicIncrement32(&Self.nextID)

    var name: String
    var productName: String?
    var vendorID: Int?
    var productID: Int?
    var serialNumber: String?
    var buttonCount: Int?
    var batteryLevel: Int?
    private let categoryValue: Category

    private weak var manager: DeviceManager?
    private var inputReportHandlers: [InputReportHandler] = []
    private var logitechReprogrammableControlsMonitor: LogitechReprogrammableControlsMonitor?
    private let device: PointerDevice

    var pointerDevice: PointerDevice {
        device
    }

    private var removed = false

    private var verbosedLoggingOn = Defaults[.verbosedLoggingOn]

    private let initialPointerResolution: Double

    private var inputObservationToken: ObservationToken?
    private var reportObservationToken: ObservationToken?

    private var lastButtonStates: UInt8 = 0

    var category: Category {
        categoryValue
    }

    init(_ manager: DeviceManager, _ device: PointerDevice) {
        self.manager = manager
        self.device = device

        vendorID = device.vendorID
        productID = device.productID
        serialNumber = device.serialNumber
        buttonCount = device.buttonCount

        let rawProductName = device.product
        let rawName = rawProductName ?? device.name
        name = rawName
        productName = rawProductName
        batteryLevel = nil
        categoryValue = Self.detectCategory(for: device)

        initialPointerResolution =
            device.pointerResolution ?? Self.fallbackPointerResolution

        // TODO: More elegant way?
        inputObservationToken = device.observeInput { [weak self] in
            self?.inputValueCallback($0, $1)
        }

        // Some bluetooth devices, such as Mi Dual Mode Wireless Mouse Silent Edition, report only
        // 3 buttons in the HID report descriptor. As a result, macOS does not recognize side button
        // clicks from these devices.
        //
        // To work around this issue, we subscribe to the input reports and monitor the side button
        // states. When the side buttons are clicked, we simulate those events.
        if let vendorID, let productID {
            let handlers = InputReportHandlerRegistry.handlers(for: vendorID, productID: productID)
            let needsObservation = handlers.contains { $0.alwaysNeedsReportObservation() } || buttonCount == 3
            if needsObservation, !handlers.isEmpty {
                inputReportHandlers = handlers
                reportObservationToken = device.observeReport { [weak self] in
                    self?.inputReportCallback($0, $1)
                }
            }
        }

        if LogitechReprogrammableControlsMonitor.supports(device: self) {
            let monitor = LogitechReprogrammableControlsMonitor(device: self)
            logitechReprogrammableControlsMonitor = monitor
            monitor.start()
        }

        os_log(
            "Device initialized: %{public}@: HIDPointerResolution=%{public}f, HIDPointerAccelerationType=%{public}@, battery=%{public}@",
            log: Self.log,
            type: .info,
            String(describing: device),
            initialPointerResolution,
            device.pointerAccelerationType ?? "(unknown)",
            batteryLevel.map { "\($0)%" } ?? "(unknown)"
        )

        Defaults.observe(.verbosedLoggingOn) { [weak self] change in
            guard let self else {
                return
            }

            verbosedLoggingOn = change.newValue
        }
        .tieToLifetime(of: self)
    }

    func markRemoved() {
        removed = true

        inputObservationToken = nil
        reportObservationToken = nil
        logitechReprogrammableControlsMonitor?.stop()
        logitechReprogrammableControlsMonitor = nil
    }

    func markActive(reason: String) {
        manager?.markDeviceActive(self, reason: reason)
    }

    var hasLogitechControlsMonitor: Bool {
        logitechReprogrammableControlsMonitor != nil
    }
}

extension Device {
    enum Category {
        case mouse, trackpad
    }

    private static let appleVendorIDs = Set([0x004C, 0x05AC])
    private static let appleMagicMouseProductIDs = Set([0x0269, 0x030D])
    private static let appleMagicTrackpadProductIDs = Set([0x0265, 0x030E])
    private static let appleBuiltInTrackpadProductIDs = Set([0x0273, 0x0276, 0x0278, 0x0340])

    private static func detectCategory(for device: PointerDevice) -> Category {
        if let vendorID = device.vendorID,
           let productID = device.productID,
           isAppleMagicMouse(vendorID: vendorID, productID: productID) {
            return .mouse
        }

        if device.confirmsTo(kHIDPage_Digitizer, kHIDUsage_Dig_TouchPad) {
            return .trackpad
        }

        return .mouse
    }

    private static func isAppleMagicMouse(vendorID: Int, productID: Int) -> Bool {
        appleVendorIDs.contains(vendorID)
            && appleMagicMouseProductIDs.contains(productID)
    }

    private static func isAppleMagicTrackpad(vendorID: Int, productID: Int) -> Bool {
        appleVendorIDs.contains(vendorID)
            && appleMagicTrackpadProductIDs.contains(productID)
    }

    private static func isAppleBuiltInTrackpad(vendorID: Int, productID: Int) -> Bool {
        vendorID == 0x05AC
            && appleBuiltInTrackpadProductIDs.contains(productID)
    }

    var showsPointerSpeedLimitationNotice: Bool {
        guard let vendorID, let productID else {
            return false
        }

        return Self.isAppleMagicMouse(vendorID: vendorID, productID: productID)
            || Self.isAppleMagicTrackpad(vendorID: vendorID, productID: productID)
            || Self.isAppleBuiltInTrackpad(vendorID: vendorID, productID: productID)
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
            guard device.useLinearScalingMouseAcceleration != nil, let newValue else {
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
            os_log(
                "Update pointer acceleration for device: %{public}@: %{public}f",
                log: Self.log,
                type: .info,
                String(describing: self),
                newValue
            )
            device.pointerAcceleration = newValue
        }
    }

    private static let pointerSpeedRange = 1.0 / 1200 ... 1.0 / 40

    static func pointerSpeed(fromPointerResolution pointerResolution: Double)
        -> Double {
        (1 / pointerResolution).normalized(from: pointerSpeedRange)
    }

    static func pointerResolution(fromPointerSpeed pointerSpeed: Double)
        -> Double {
        1 / (pointerSpeed.normalized(to: pointerSpeedRange))
    }

    var pointerSpeed: Double {
        get {
            device.pointerResolution.map {
                Self.pointerSpeed(fromPointerResolution: $0)
            }
                ?? Self
                .fallbackPointerSpeed
        }
        set {
            os_log(
                "Update pointer speed for device: %{public}@: %{public}f",
                log: Self.log,
                type: .info,
                String(describing: self),
                newValue
            )
            device.pointerResolution = Self.pointerResolution(fromPointerSpeed: newValue)
        }
    }

    func restorePointerAcceleration() {
        let systemPointerAcceleration = (DeviceManager.shared
            .getSystemProperty(forKey: device.pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey) as IOFixed?
        )
        .map { Double($0) / 65_536 } ?? Self.fallbackPointerAcceleration

        os_log(
            "Restore pointer acceleration for device: %{public}@: %{public}f",
            log: Self.log,
            type: .info,
            String(describing: device),
            systemPointerAcceleration
        )

        pointerAcceleration = systemPointerAcceleration
    }

    func restorePointerSpeed() {
        os_log(
            "Restore pointer speed for device: %{public}@: %{public}f",
            log: Self.log,
            type: .info,
            String(describing: device),
            Self.pointerSpeed(fromPointerResolution: initialPointerResolution)
        )

        device.pointerResolution = initialPointerResolution
    }

    func restorePointerAccelerationAndPointerSpeed() {
        restorePointerSpeed()
        restorePointerAcceleration()
    }

    private func inputValueCallback(
        _ device: PointerDevice, _ value: IOHIDValue
    ) {
        if verbosedLoggingOn {
            os_log(
                "Received input value from: %{public}@: %{public}@",
                log: Self.log,
                type: .info,
                String(describing: device),
                String(describing: value)
            )
        }

        guard let manager else {
            os_log("manager is nil", log: Self.log, type: .error)
            return
        }

        guard manager.lastActiveDeviceId != id else {
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

        manager.markDeviceActive(
            self,
            reason: "Received input value: usagePage=0x\(String(format: "%02X", usagePage)), usage=0x\(String(format: "%02X", usage))"
        )
    }

    private func inputReportCallback(_ device: PointerDevice, _ report: Data) {
        if verbosedLoggingOn {
            let reportHex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
            os_log(
                "Received input report from: %{public}@: %{public}@",
                log: Self.log,
                type: .info,
                String(describing: device),
                String(describing: reportHex)
            )
        }

        let context = InputReportContext(report: report, lastButtonStates: lastButtonStates)
        let chain = inputReportHandlers.reversed().reduce({ (_: InputReportContext) in }) { next, handler in
            { context in handler.handleReport(context, next: next) }
        }
        chain(context)
        lastButtonStates = context.lastButtonStates
    }
}

extension Device: Hashable {
    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension Device: CustomStringConvertible {
    var description: String {
        let vendorIDString = vendorID.map { String(format: "0x%04X", $0) } ?? "(nil)"
        let productIDString = productID.map { String(format: "0x%04X", $0) } ?? "(nil)"
        return String(format: "%@ (VID=%@, PID=%@)", name, vendorIDString, productIDString)
    }
}
