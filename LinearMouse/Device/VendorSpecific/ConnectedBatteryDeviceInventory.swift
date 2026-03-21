// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import IOKit.hid

struct ConnectedBatteryDeviceInfo: Hashable {
    let name: String
    let batteryLevel: Int
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

            let key = "\(result.name)|\(result.batteryLevel)"
            guard seen.insert(key).inserted else {
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

        return ConnectedBatteryDeviceInfo(name: name, batteryLevel: batteryLevel)
    }

    private static func isGenericLogitechReceiver(name: String, hidDevice: IOHIDDevice) -> Bool {
        guard let vendorID: NSNumber = getProperty(kIOHIDVendorIDKey, from: hidDevice),
              vendorID.intValue == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
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
