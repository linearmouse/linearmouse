// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation

extension IOHIDServiceClient {
    private func getService() -> io_service_t? {
        guard let registryID = IOHIDServiceClientGetRegistryID(self) as? UInt64 else {
            return nil
        }

        guard let matching = IORegistryEntryIDMatching(registryID) else {
            return nil
        }

        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }

        var service = IOServiceGetMatchingService(mainPort, matching)
        guard service != 0 else {
            return nil
        }

        if IOObjectConformsTo(service, "IOHIDDevice") != MACH_PORT_NULL {
            return service
        }

        var iter = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            service,
            "IOService",
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents),
            &iter
        ) == KERN_SUCCESS else {
            IOObjectRelease(service)
            return nil
        }
        defer { IOObjectRelease(iter) }

        while true {
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
            guard service != MACH_PORT_NULL else {
                break
            }
            if IOObjectConformsTo(service, "IOHIDDevice") != 0 {
                return service
            }
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
