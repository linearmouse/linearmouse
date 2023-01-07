// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Defaults

struct DeviceMatcher: Codable, Defaults.Serializable {
    @HexRepresentation var vendorID: Int?
    @HexRepresentation var productID: Int?
    var productName: String?
    var serialNumber: String?
    @SingleValueOrArray var category: [Category]?

    enum Category: String, Codable {
        case mouse, trackpad
    }
}

extension DeviceMatcher {
    init(of device: Device) {
        self.init(vendorID: device.vendorID,
                  productID: device.productID,
                  productName: device.productName,
                  serialNumber: device.serialNumber,
                  category: [Category(from: device.category)])
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
              matchValue(productName, device.productName),
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
