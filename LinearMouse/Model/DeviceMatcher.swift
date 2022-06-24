// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Defaults

struct DeviceMatcher: Codable, Defaults.Serializable {
    @HexRepresentation var vendorID: Int?
    @HexRepresentation var productID: Int?
    var serialNumber: String?
    @SingleValueOrArray var category: [Category]?

    enum Category: String, Codable {
        case mouse, trackpad
    }
}

extension DeviceMatcher {
    init(of device: Device) {
        let vendorID = device.vendorID
        let productID = device.productID
        let serialNumber = device.serialNumber
        let category = [Category(from: device.category)]

        self.init(vendorID: vendorID, productID: productID, serialNumber: serialNumber, category: category)
    }

    func match(with device: Device) -> Bool {
        func matchValue<T>(_ destination: T?, _ source: T) -> Bool where T: Equatable {
            destination == nil || source == destination
        }

        func matchValue<T>(_ destination: T?, _ source: T?) -> Bool where T: Equatable {
            destination == nil || source == destination
        }

        guard matchValue(vendorID, device.vendorID),
              matchValue(productID, device.productID),
              matchValue(serialNumber, device.serialNumber)
        else {
            return false
        }

        if let category = category {
            guard category.contains(where: { $0.deviceCategory == device.category })
            else {
                return false
            }
        }

        return true
    }
}

extension DeviceMatcher.Category {
    init(from deviceCategory: Device.Category) {
        switch deviceCategory {
        case .mouse:
            self = .mouse
        case .trackpad:
            self = .trackpad
        }
    }

    var deviceCategory: Device.Category {
        switch self {
        case .mouse:
            return .mouse
        case .trackpad:
            return .trackpad
        }
    }
}
