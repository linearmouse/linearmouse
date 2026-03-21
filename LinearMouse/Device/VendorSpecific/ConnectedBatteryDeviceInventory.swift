// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import IOKit.hid

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

        for hidDevice in hidDevices {
            guard let result = batteryDeviceInfo(for: hidDevice) else {
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

    private static func batteryDeviceInfo(for hidDevice: IOHIDDevice) -> ConnectedBatteryDeviceInfo? {
        let candidateKeys = [
            "BatteryPercent",
            "BatteryLevel",
            "BatteryPercentRemaining",
            "BatteryPercentSingle"
        ]

        let batteryLevel = candidateKeys.lazy
            .compactMap { key -> Int? in
                if let value: NSNumber = getProperty(key, from: hidDevice) {
                    return value.intValue
                }

                return nil
            }
            .first

        guard let batteryLevel else {
            return nil
        }

        let name: String = getProperty(kIOHIDProductKey, from: hidDevice) ?? "(unknown)"

        if isGenericLogitechReceiver(name: name, hidDevice: hidDevice) {
            return nil
        }

        let vendorID: NSNumber? = getProperty(kIOHIDVendorIDKey, from: hidDevice)
        let productID: NSNumber? = getProperty(kIOHIDProductIDKey, from: hidDevice)
        let serialNumber: String? = getProperty(kIOHIDSerialNumberKey, from: hidDevice)
        let locationID: NSNumber? = getProperty("LocationID", from: hidDevice)
        let transport: String? = getProperty("Transport", from: hidDevice)

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
}
