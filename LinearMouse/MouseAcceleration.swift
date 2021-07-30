//
//  MouseAcceleration.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/13.
//

import Foundation

enum MouseAccelerationValue {
    static let accelerationOff = -65536
    static let accelerationOn = 45056
}

class MouseAcceleration {
    private var service: io_registry_entry_t?
    private var handle: io_connect_t?
    private var timer: Timer?

    init() {
        let service = IORegistryEntryFromPath(kIOMasterPortDefault, "\(kIOServicePlane):/IOResources/IOHIDSystem")
        guard service != .zero else { return }
        self.service = service

        var handle = NXEventHandle(MACH_PORT_NULL)
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &handle) == KERN_SUCCESS else { return }
        self.handle = handle
    }

    deinit {
        if let handle = handle {
            IOServiceClose(handle)
        }
        if let service = service {
            IOObjectRelease(service)
        }
    }

    public var acceleration: Int {
        get {
            guard let handle = handle else { return 0 }

            var typeRef: Unmanaged<CFTypeRef>?
            guard IOHIDCopyCFTypeParameter(handle, kIOHIDMouseAccelerationType as CFString?, &typeRef) == KERN_SUCCESS else { return 0 }
            guard let typeRefUnwrapped = typeRef else { return 0 }
            defer { typeRefUnwrapped.release() }

            var acceleration = 0
            CFNumberGetValue((typeRefUnwrapped.takeUnretainedValue() as! CFNumber), CFNumberType.sInt32Type, &acceleration)
            return acceleration
        }

        set {
            let service = IORegistryEntryFromPath(kIOMasterPortDefault, "\(kIOServicePlane):/IOResources/IOHIDSystem")
            guard service != .zero else { return }
            defer { IOObjectRelease(service) }

            var handle: io_connect_t = .zero
            guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &handle) == KERN_SUCCESS else { return }
            defer { IOServiceClose(handle) }

            var value = NSInteger(newValue)
            let number = CFNumberCreate(kCFAllocatorDefault, CFNumberType.sInt32Type, &value)
            guard IOHIDSetCFTypeParameter(handle, "HIDMouseAcceleration" as CFString, number) == KERN_SUCCESS else { return }
        }
    }

    func enable() {
        if let timer = timer {
            self.timer = nil
            timer.invalidate()
        }
        DispatchQueue.main.async {
            self.acceleration = MouseAccelerationValue.accelerationOn
        }
    }

    func disable() {
        guard timer == nil else { return }
        self.acceleration = MouseAccelerationValue.accelerationOff
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { timer in
            DispatchQueue.main.async {
                self.acceleration = MouseAccelerationValue.accelerationOff
            }
        }
    }
}
