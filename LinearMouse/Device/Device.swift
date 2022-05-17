//
//  Device.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/14.
//

import Foundation
import os.log

class Device {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Device")

    private static let fallbackPointerAccelerationInt = 45056

    private let serviceClient: IOHIDServiceClient
    private let initialPointerResolution: Int
    private var pointerAccelerationType: String
    private var device: IOHIDDevice

    init?(serviceClient: IOHIDServiceClient) {
        self.serviceClient = serviceClient
        guard let pointerResolution: Int = serviceClient.getProperty(kIOHIDPointerResolutionKey) else {
            os_log("HIDPointerResolution not found: %{public}@", log: Self.log, type: .debug, String(describing: serviceClient))
            return nil
        }
        self.initialPointerResolution = pointerResolution
        pointerAccelerationType = serviceClient.getProperty(kIOHIDPointerAccelerationTypeKey) ?? "HIDMouseAcceleration"
        guard let device = serviceClient.device else {
            os_log("IOHIDDevice not found: %{public}@", log: Self.log, type: .debug, String(describing: serviceClient))
            return nil
        }
        self.device = device
        os_log("Device initialized: %{public}@: HIDPointerResolution=%{public}d, HIDPointerAccelerationType=%{public}@",
               log: Self.log, type: .debug,
               String(describing: serviceClient),
               pointerResolution,
               pointerAccelerationType)
    }

    func serviceClientEquals(serviceClient: IOHIDServiceClient) -> Bool {
        self.serviceClient == serviceClient
    }

    enum Category {
        case mouse, trackpad
    }

    private func isAppleMagicMouse(vendorID: Int, productID: Int) -> Bool {
        [0x004C, 0x05AC].contains(vendorID) && [0x0269, 0x030D].contains(productID)
    }

    lazy var category: Category = {
        if let vendorID: Int = serviceClient.getProperty(kIOHIDVendorIDKey),
           let productID: Int = serviceClient.getProperty(kIOHIDProductIDKey) {
            if isAppleMagicMouse(vendorID: vendorID, productID: productID) {
                return .mouse
            }
        }
        if IOHIDServiceClientConformsTo(serviceClient,
                                        UInt32(kHIDPage_Digitizer),
                                        UInt32(kHIDUsage_Dig_TouchPad)) != 0 {
            return .trackpad
        }
        return .mouse
    }()

    var pointerAcceleration: Double {
        let pointerAccelerationInt: Int = serviceClient.getProperty(pointerAccelerationType) ?? Self.fallbackPointerAccelerationInt
        return max(0, min(Double(pointerAccelerationInt) / 65536, 20))
    }

    var pointerSensitivity: Double {
        guard let pointerResolution: Double = serviceClient.getProperty(kIOHIDPointerResolutionKey) else {
            return 1600
        }
        return 2000 - (pointerResolution / 65536)
    }

    var shouldApplyPointerSpeedSettings: Bool {
        guard category == .mouse else {
            os_log("Device ignored for pointer speed settings: %@: Category is %@", log: Self.log, type: .debug,
                   String(describing: self), String(describing: category))
            return false
        }
        return true
    }

    func updatePointerSpeed(acceleration: Double, sensitivity: Double, disableAcceleration: Bool) {
        guard shouldApplyPointerSpeedSettings else {
            return
        }
        let accelerationInt = disableAcceleration ? -65536 : Int(acceleration * 65536)
        let sensitivity = max(5, min(sensitivity, 1990))
        let resolution = Int((2000 - sensitivity) * 65536)
        os_log("Update speed for device: %{public}@, %{public}@ = %{public}d, HIDPointerResolution = %{public}d",
               log: Self.log, type: .debug,
               String(describing: serviceClient), pointerAccelerationType, accelerationInt, resolution)
        serviceClient.setProperty(resolution, forKey: kIOHIDPointerResolutionKey)
        serviceClient.setProperty(accelerationInt, forKey: pointerAccelerationType)
    }

    func restorePointerSpeedToInitialValue() {
        guard shouldApplyPointerSpeedSettings else {
            return
        }
        let accelerationInt = DeviceManager.shared.getSystemProperty(forKey: pointerAccelerationType) ?? Self.fallbackPointerAccelerationInt
        let resolution = initialPointerResolution
        os_log("Revert speed for device: %{public}@, %{public}@ = %{public}d, HIDPointerResolution = %{public}d",
               log: Self.log, type: .debug,
               String(describing: serviceClient), pointerAccelerationType, accelerationInt, resolution)
        serviceClient.setProperty(resolution, forKey: kIOHIDPointerResolutionKey)
        serviceClient.setProperty(accelerationInt, forKey: pointerAccelerationType)
    }
}

extension Device: Hashable {
    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.serviceClient == rhs.serviceClient
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(serviceClient)
    }
}

extension Device: CustomStringConvertible {
    var description: String {
        serviceClient.description
    }
}
