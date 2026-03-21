// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import PointerKit

enum ConnectedLogitechDeviceInventory {
    static func devices(from pointerDevices: [PointerDevice]) -> [ConnectedBatteryDeviceInfo] {
        var results = [ConnectedBatteryDeviceInfo]()
        var seen = Set<String>()

        for device in pointerDevices where device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID {
            guard let metadata = VendorSpecificDeviceMetadataRegistry.metadata(for: device),
                  let batteryLevel = metadata.batteryLevel
            else {
                continue
            }

            let name = metadata.name ?? device.product ?? device.name
            let key = "\(name)|\(batteryLevel)"
            guard seen.insert(key).inserted else {
                continue
            }

            results.append(.init(name: name, batteryLevel: batteryLevel))
        }

        return results.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            if byName == .orderedSame {
                return $0.batteryLevel > $1.batteryLevel
            }

            return byName == .orderedAscending
        }
    }
}
