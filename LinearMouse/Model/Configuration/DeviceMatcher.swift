// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Defaults

struct DeviceMatcher: Codable, Equatable, Hashable, Defaults.Serializable {
    @HexRepresentation var vendorID: Int?
    @HexRepresentation var productID: Int?
    var productName: String?
    var serialNumber: String?
    @SingleValueOrArray var category: [Category]?

    enum Category: String, Codable, Hashable {
        case mouse, trackpad
    }
}

extension DeviceMatcher {
    init(category: Category) {
        vendorID = nil
        productID = nil
        productName = nil
        serialNumber = nil
        self.category = [category]
    }

    init(of device: Device) {
        self.init(
            vendorID: device.vendorID,
            productID: device.productID,
            productName: device.productName,
            serialNumber: device.serialNumber,
            category: [Category(from: device.category)]
        )
    }

    func match(with device: Device) -> Bool {
        func matchValue<T: Equatable>(_ destination: T?, _ source: T) -> Bool {
            destination == nil || source == destination
        }

        func matchValue<T: Equatable>(_ destination: T?, _ source: T?) -> Bool {
            destination == nil || source == destination
        }

        guard matchValue(vendorID, device.vendorID),
              matchValue(productID, device.productID),
              matchValue(productName, device.productName),
              matchValue(serialNumber, device.serialNumber)
        else {
            return false
        }

        if let category {
            guard category.contains(where: { $0.deviceCategory == device.category }) else {
                return false
            }
        }

        return true
    }

    func match(with matcher: DeviceMatcher) -> Bool {
        func matchValue<T: Equatable>(_ destination: T?, _ source: T?) -> Bool {
            destination == nil || source == destination
        }

        guard matchValue(vendorID, matcher.vendorID),
              matchValue(productID, matcher.productID),
              matchValue(productName, matcher.productName),
              matchValue(serialNumber, matcher.serialNumber)
        else {
            return false
        }

        if let category {
            guard let matcherCategory = matcher.category,
                  category.contains(where: { matcherCategory.contains($0) })
            else {
                return false
            }
        }

        return true
    }

    var categoryOnlyValue: Category? {
        guard vendorID == nil,
              productID == nil,
              productName == nil,
              serialNumber == nil,
              let category,
              category.count == 1
        else {
            return nil
        }

        return category.first
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
