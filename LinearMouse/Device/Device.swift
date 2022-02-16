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

    private let serviceClient: IOHIDServiceClient
    private let pointerResolution: Int
    private var pointerAccelerationType: String
    private let pointerAcceleration: Int
    private var device: IOHIDDevice

    init?(serviceClient: IOHIDServiceClient) {
        self.serviceClient = serviceClient
        guard let pointerResolution: Int = serviceClient.getProperty(kIOHIDPointerResolutionKey) else {
            os_log("HIDPointerResolution not found: %{public}@", log: Self.log, type: .debug, String(describing: serviceClient))
            return nil
        }
        self.pointerResolution = pointerResolution
        pointerAccelerationType = serviceClient.getProperty(kIOHIDPointerAccelerationTypeKey) ?? "HIDMouseAcceleration"
        pointerAcceleration = serviceClient.getProperty(pointerAccelerationType) ?? 45056
        guard let device = serviceClient.device else {
            os_log("IOHIDDevice not found: %{public}@", log: Self.log, type: .debug, String(describing: serviceClient))
            return nil
        }
        self.device = device
        os_log("Device initialized: %{public}@: HIDPointerResolution=%{public}d, %{public}@=%{public}d",
               log: Self.log, type: .debug,
               String(describing: serviceClient),
               pointerResolution,
               pointerAccelerationType,
               pointerAcceleration)
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

    var acceleration: Double {
        let pointerAcceleration: Int = serviceClient.getProperty(pointerAccelerationType) ?? self.pointerAcceleration
        return max(0, min(Double(pointerAcceleration) / 65536, 20))
    }

    var sensitivity: Int {
        guard let pointerResolution: Int = serviceClient.getProperty(kIOHIDPointerResolutionKey) else {
            return 1600
        }
        return 2000 - (pointerResolution >> 16)
    }

    func updateSpeed(acceleration: Double, sensitivity: Int, disableAcceleration: Bool) {
        let acceleration = disableAcceleration ? -65536 : Int(acceleration * 65536)
        let sensitivity = max(5, min(sensitivity, 1990))
        let resolution = (2000 - sensitivity) << 16
        os_log("Update speed for device: %{public}@, %{public}@ = %{public}d, HIDPointerResolution = %{public}d",
               log: Self.log, type: .debug,
               String(describing: serviceClient), pointerAccelerationType, acceleration, resolution)
        serviceClient.setProperty(resolution, forKey: kIOHIDPointerResolutionKey)
        serviceClient.setProperty(acceleration, forKey: pointerAccelerationType)
    }

    func revertSpeed() {
        os_log("Revert speed for device: %{public}@, %{public}@ = %{public}d, HIDPointerResolution = %{public}d",
               log: Self.log, type: .debug,
               String(describing: serviceClient), pointerAccelerationType, pointerAcceleration, pointerResolution)
        serviceClient.setProperty(pointerResolution, forKey: kIOHIDPointerResolutionKey)
        serviceClient.setProperty(pointerAcceleration, forKey: pointerAccelerationType)
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
