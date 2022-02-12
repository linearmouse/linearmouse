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
            self.lastActiveService = service
            self.lastActiveServiceType = {
                if IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) != 0 {
                    return .trackpad
                }
                return .mouse
            }()
            os_log("switched to: %{public}@, reported as %{public}@", log: ExperimentalMouseDetector.log, type: .debug,
                   product, String(describing: self.lastActiveServiceType))
        }, nil, nil)
        IOHIDEventSystemClientScheduleWithDispatchQueue(client, DispatchQueue.main)
    }

    func isMouseEvent(_ event: CGEvent) -> Bool {
        lastActiveServiceType == .mouse
    }
}
