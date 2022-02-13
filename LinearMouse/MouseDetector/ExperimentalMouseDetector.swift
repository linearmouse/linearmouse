//
//  ExperimentalMouseDetector.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/12.
//

import Foundation
import os.log

class ExperimentalMouseDetector: MouseDetector {
    private let client: IOHIDEventSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault).takeRetainedValue()
    private var lastActiveService: IOHIDServiceClient?
    private var lastActiveServiceType: DeviceType = .unknown

    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ExperimentalMouseDetector")

    enum DeviceType {
        case unknown, trackpad, mouse
    }

    init() {
        let match1 = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ] as CFDictionary
        let match2 = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer
        ] as CFDictionary
        let match3 = [
            kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer,
            kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchPad
        ] as CFDictionary
        IOHIDEventSystemClientSetMatchingMultiple(client, [match1, match2, match3] as CFArray)
        IOHIDEventSystemClientRegisterEventBlock(client, { _, _, sender, event in
            guard let service = sender else {
                return
            }
            guard service != self.lastActiveService else {
                return
            }
            guard let productRef = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) else {
                return
            }
            guard let product = productRef as? String else {
                return
            }
            guard let vendorIDRef = IOHIDServiceClientCopyProperty(service, kIOHIDVendorIDKey as CFString) else {
                return
            }
            guard let vendorID = vendorIDRef as? Int else {
                return
            }
            guard let productIDRef = IOHIDServiceClientCopyProperty(service, kIOHIDProductIDKey as CFString) else {
                return
            }
            guard let productID = productIDRef as? Int else {
                return
            }
            self.lastActiveService = service
            self.lastActiveServiceType = {
                if IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) == 0 {
                    return .mouse
                }
                if (vendorID == 0x004c || vendorID == 0x05ac) && (productID == 0x0269 || productID == 0x030d) {
                    return .mouse
                }
                return .trackpad
            }()
            os_log("switched to: %{public}@ (vid=0x%{public}04x, pid=0x%{public}04x), type: %{public}@",
                   log: ExperimentalMouseDetector.log, type: .debug,
                   product, vendorID, productID, String(describing: self.lastActiveServiceType))
        }, nil, nil)
        IOHIDEventSystemClientScheduleWithDispatchQueue(client, DispatchQueue.main)
    }

    func isMouseEvent(_ event: CGEvent) -> Bool {
        lastActiveServiceType == .mouse
    }
}
