// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation

extension IOHIDServiceClient {
    private func getService() -> io_service_t? {
        guard let registryID = IOHIDServiceClientGetRegistryID(self) as? UInt64 else {
            return nil
        }
        guard let matching = IORegistryEntryIDMatching(registryID) else {
            return nil
        }
        let mainPort: mach_port_t = {
            if #available(macOS 12.0, *) {
                return kIOMainPortDefault
            } else {
                return kIOMasterPortDefault
            }
        }()
        let service = IOServiceGetMatchingService(mainPort, matching)
        guard service != 0 else {
            return nil
        }
        if IOObjectConformsTo(service, "IOHIDDevice") != MACH_PORT_NULL {
            return service
        }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            service,
            "IOService",
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents),
            &iterator
        ) == KERN_SUCCESS else {
            IOObjectRelease(service)
            return nil
        }
        IOObjectRelease(service)
        while true {
            let service = IOIteratorNext(iterator)
            guard service != MACH_PORT_NULL else {
                break
            }
            if IOObjectConformsTo(service, "IOHIDDevice") != 0 {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    var device: IOHIDDevice? {
        guard let service = getService() else {
            return nil
        }
        defer { IOObjectRelease(service) }
        return IOHIDDeviceCreate(kCFAllocatorDefault, service)
    }
}
