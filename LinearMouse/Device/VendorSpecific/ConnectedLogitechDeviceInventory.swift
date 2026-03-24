// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import PointerKit

enum ConnectedLogitechDeviceInventory {
    static func devices(from pointerDevices: [PointerDevice]) -> [ConnectedBatteryDeviceInfo] {
        var results = [ConnectedBatteryDeviceInfo]()
        var seen = Set<String>()

        for device in pointerDevices where device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID {
            let productName = device.product ?? device.name
            if device.transport == PointerDeviceTransportName.usb,
               productName.localizedCaseInsensitiveContains("receiver") {
                continue
            }

            guard let metadata = VendorSpecificDeviceMetadataRegistry.metadata(for: device),
                  let batteryLevel = metadata.batteryLevel
            else {
                continue
            }

            let name = metadata.name ?? productName
            let identity = ConnectedBatteryDeviceInfo.directIdentity(
                vendorID: device.vendorID,
                productID: device.productID,
                serialNumber: device.serialNumber,
                locationID: device.locationID,
                transport: device.transport,
                fallbackName: name
            )
            guard seen.insert(identity).inserted else {
                continue
            }

            results.append(.init(id: identity, name: name, batteryLevel: batteryLevel))
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
