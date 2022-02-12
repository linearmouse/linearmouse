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
    private var lastActiveServiceType: DeviceType = .mouse

    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ExperimentalMouseDetector")

    enum DeviceType {
        case mouse, trackpad
    }

    init() {
        let match1 = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]
        let match2 = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer
        ]
        IOHIDEventSystemClientSetMatchingMultiple(client, [match1 as CFDictionary, match2 as CFDictionary] as CFArray)
        IOHIDEventSystemClientRegisterEventCallback(client, { target, _, sender, event in
            // TODO: Weak self reference?
            guard let unwrappedTarget = target else {
                return
            }
            let this = Unmanaged<ExperimentalMouseDetector>.fromOpaque(unwrappedTarget).takeUnretainedValue()
            guard let service = sender else {
                return
            }
            guard service != this.lastActiveService else {
                return
            }
            guard let productRef = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) else {
                return
            }
            guard let product = productRef as? String else {
                return
            }
            this.lastActiveService = service
            this.lastActiveServiceType = {
                if IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) != 0 {
                    return .trackpad
                }
                return .mouse
            }()
            os_log("switched to: %{public}@, reported as %{public}@", log: ExperimentalMouseDetector.log, type: .debug,
                   product, String(describing: this.lastActiveServiceType))
        }, Unmanaged.passUnretained(self).toOpaque(), nil)
        IOHIDEventSystemClientScheduleWithDispatchQueue(client, DispatchQueue.main)
    }

    func isMouseEvent(_ event: CGEvent) -> Bool {
        lastActiveServiceType == .mouse
    }
}
