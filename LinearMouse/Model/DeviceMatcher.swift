// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Defaults

struct DeviceMatcher: Codable, Defaults.Serializable, Equatable {
    let vendorID: HexValue?
    let productID: HexValue?
    let serialNumber: String?
}

extension DeviceMatcher {
    init(of device: Device) {
        let vendorID = HexValue(device.vendorID)
        let productID = HexValue(device.productID)
        let serialNumber = device.serialNumber

        self.init(vendorID: vendorID, productID: productID, serialNumber: serialNumber)
    }

    func match(with device: Device) -> Bool {
        func matchValue<T>(_ destination: T?, _ source: T) -> Bool where T: Equatable {
            destination == nil || source == destination
        }

        guard matchValue(vendorID?.value, device.vendorID),
              matchValue(productID?.value, device.productID),
              matchValue(serialNumber, device.serialNumber) else {
            return false
        }

        return true
    }
}
