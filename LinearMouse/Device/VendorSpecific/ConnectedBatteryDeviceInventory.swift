// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import IOKit.hid
import PointerKit

private typealias AppleBatterySnapshot = (id: String, level: Int)

struct ConnectedBatteryDeviceInfo: Hashable {
    let id: String
    let name: String
    let batteryLevel: Int

    static func directIdentity(
        vendorID: Int?,
        productID: Int?,
        serialNumber: String?,
        locationID: Int?,
        transport: String?,
        fallbackName: String
    ) -> String {
        if let serialNumber, !serialNumber.isEmpty {
            return "serial|\(vendorID ?? 0)|\(productID ?? 0)|\(serialNumber)"
        }

        if let locationID {
            return "location|\(vendorID ?? 0)|\(productID ?? 0)|\(locationID)"
        }

        return "fallback|\(transport ?? "")|\(vendorID ?? 0)|\(productID ?? 0)|\(fallbackName)"
    }

    static func receiverIdentity(receiverLocationID: Int, slot: UInt8) -> String {
        "receiver|\(receiverLocationID)|\(slot)"
    }

    static func currentDeviceBatteryLevel(
        pairedDevices: [ReceiverLogicalDeviceIdentity],
        directDeviceIdentity: String?,
        inventory: [Self]
    ) -> Int? {
        let pairedBatteryLevels = pairedDevices.compactMap(\.batteryLevel)
        if let lowestPairedBatteryLevel = pairedBatteryLevels.min() {
            return lowestPairedBatteryLevel
        }

        guard let directDeviceIdentity else {
            return nil
        }

        return inventory.first { $0.id == directDeviceIdentity }?.batteryLevel
    }

    static func isAppleBluetoothDevice(vendorID: Int?, transport: String?) -> Bool {
        vendorID == 0x004C && transport == PointerDeviceTransportName.bluetooth
    }
}

enum ConnectedBatteryDeviceInventory {
    static func devices() -> [ConnectedBatteryDeviceInfo] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return []
        }

        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let hidDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        var results = [ConnectedBatteryDeviceInfo]()
        var seen = Set<String>()
        let appleBatterySnapshots = appleBluetoothBatterySnapshots()

        for hidDevice in hidDevices {
            guard let result = batteryDeviceInfo(for: hidDevice, appleBatterySnapshots: appleBatterySnapshots) else {
                continue
            }

            guard seen.insert(result.id).inserted else {
                continue
            }

            results.append(result)
        }

        return results.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            if byName == .orderedSame {
                return $0.batteryLevel > $1.batteryLevel
            }

            return byName == .orderedAscending
        }
    }

    private static func batteryDeviceInfo(
        for hidDevice: IOHIDDevice,
        appleBatterySnapshots: [AppleBatterySnapshot]
    ) -> ConnectedBatteryDeviceInfo? {
        let vendorID: NSNumber? = getProperty(kIOHIDVendorIDKey, from: hidDevice)
        let productID: NSNumber? = getProperty(kIOHIDProductIDKey, from: hidDevice)
        let serialNumber: String? = getProperty(kIOHIDSerialNumberKey, from: hidDevice)
        let locationID: NSNumber? = getProperty("LocationID", from: hidDevice)
        let transport: String? = getProperty("Transport", from: hidDevice)

        let candidateKeys = [
            "BatteryPercent",
            "BatteryLevel",
            "BatteryPercentRemaining",
            "BatteryPercentSingle"
        ]

        let directBatteryLevel = candidateKeys.lazy
            .compactMap { key -> Int? in
                if let value: NSNumber = getProperty(key, from: hidDevice) {
                    return value.intValue
                }

                return nil
            }
            .first

        let batteryLevel = directBatteryLevel
            ?? fallbackAppleBluetoothBatteryLevel(
                vendorID: vendorID?.intValue,
                productID: productID?.intValue,
                serialNumber: serialNumber,
                locationID: locationID?.intValue,
                transport: transport,
                appleBatterySnapshots: appleBatterySnapshots
            )

        guard let batteryLevel else {
            return nil
        }

        let name: String = getProperty(kIOHIDProductKey, from: hidDevice) ?? "(unknown)"

        if isGenericLogitechReceiver(name: name, hidDevice: hidDevice) {
            return nil
        }

        return ConnectedBatteryDeviceInfo(
            id: ConnectedBatteryDeviceInfo.directIdentity(
                vendorID: vendorID?.intValue,
                productID: productID?.intValue,
                serialNumber: serialNumber,
                locationID: locationID?.intValue,
                transport: transport,
                fallbackName: name
            ),
            name: name,
            batteryLevel: batteryLevel
        )
    }

    private static func isGenericLogitechReceiver(name: String, hidDevice: IOHIDDevice) -> Bool {
        guard let vendorID: NSNumber = getProperty(kIOHIDVendorIDKey, from: hidDevice),
              vendorID.intValue == 0x046D
        else {
            return false
        }

        return name.localizedCaseInsensitiveContains("receiver")
    }

    private static func getProperty<T>(_ key: String, from device: IOHIDDevice) -> T? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        return value as? T
    }

    private static func fallbackAppleBluetoothBatteryLevel(
        vendorID: Int?,
        productID: Int?,
        serialNumber: String?,
        locationID: Int?,
        transport: String?,
        appleBatterySnapshots: [AppleBatterySnapshot]
    ) -> Int? {
        guard ConnectedBatteryDeviceInfo.isAppleBluetoothDevice(vendorID: vendorID, transport: transport) else {
            return nil
        }

        let directID = ConnectedBatteryDeviceInfo.directIdentity(
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            locationID: locationID,
            transport: transport,
            fallbackName: ""
        )

        return appleBatterySnapshots.first { $0.id == directID }?.level
    }

    private static func appleBluetoothBatterySnapshots() -> [AppleBatterySnapshot] {
        var snapshots = [AppleBatterySnapshot]()
        var iterator = io_iterator_t()

        guard IOServiceGetMatchingServices(
            kIOMasterPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }

        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != MACH_PORT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let vendorIDNumber = IORegistryEntryCreateCFProperty(
                service,
                kIOHIDVendorIDKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber,
                let transport = IORegistryEntryCreateCFProperty(
                    service,
                    "Transport" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? String,
                let batteryLevel = IORegistryEntryCreateCFProperty(
                    service,
                    "BatteryPercent" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? NSNumber,
                ConnectedBatteryDeviceInfo.isAppleBluetoothDevice(
                    vendorID: vendorIDNumber.intValue,
                    transport: transport
                )
            else {
                continue
            }

            let productID = (IORegistryEntryCreateCFProperty(
                service,
                kIOHIDProductIDKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber)?.intValue
            let serialNumber = IORegistryEntryCreateCFProperty(
                service,
                kIOHIDSerialNumberKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String
            let locationID = (IORegistryEntryCreateCFProperty(
                service,
                "LocationID" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber)?.intValue

            let id = ConnectedBatteryDeviceInfo.directIdentity(
                vendorID: vendorIDNumber.intValue,
                productID: productID,
                serialNumber: serialNumber,
                locationID: locationID,
                transport: transport,
                fallbackName: ""
            )
            snapshots.append((id: id, level: batteryLevel.intValue))
        }

        return snapshots
    }
}
