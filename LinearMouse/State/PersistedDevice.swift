// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Defaults

struct PersistedDevice: Codable, Defaults.Serializable {
    let vendorID: Int?
    let productID: Int?
    let serialNumber: String?
}

extension PersistedDevice {
    init(fromDevice device: Device) {
        let vendorID = device.vendorID
        let productID = device.productID
        let serialNumber = device.serialNumber

        self.init(vendorID: vendorID, productID: productID, serialNumber: serialNumber)
    }

    func strictMatch(with device: Device) -> Bool {
        device.vendorID == vendorID && device.productID == productID && device.serialNumber == serialNumber
    }
}
