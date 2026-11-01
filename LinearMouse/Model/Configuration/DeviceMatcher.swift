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

    /// The physical device as macOS reports it, such as a USB receiver.
    init(of device: Device) {
        self.init(
            vendorID: device.vendorID,
            productID: device.productID,
            productName: device.productName,
            serialNumber: device.serialNumber,
            category: [Category(from: device.category)]
        )
    }

    /// A logical device behind `device`, such as a mouse paired to one slot
    /// of a Logitech receiver. Its identity is the one the same device reports
    /// when connected directly, so one scheme covers every connection.
    /// Nil when the identity is too weak to tell devices apart.
    init?(of device: Device, logicalDevice identity: ReceiverLogicalDeviceIdentity) {
        guard identity.productID != nil || identity.serialNumber != nil else {
            return nil
        }

        self.init(
            vendorID: device.vendorID,
            productID: identity.productID,
            productName: identity.name,
            serialNumber: identity.serialNumber,
            category: [Category(from: device.category)]
        )
    }

    /// The device the user is actually using: the logical device the physical
    /// device currently routes to, or the physical device itself.
    init(activeOf device: Device) {
        self = Self.candidates(of: device)[0]
    }

    /// Every identity a scheme can match the device by, most specific first.
    /// Schemes written for a receiver keep applying to the devices behind it.
    static func candidates(of device: Device) -> [DeviceMatcher] {
        let physical = DeviceMatcher(of: device)
        guard let identity = device.activeLogicalDeviceIdentity,
              let logical = DeviceMatcher(of: device, logicalDevice: identity) else {
            return [physical]
        }

        return [logical, physical]
    }

    /// The condition to create when the user selects this matcher. For a
    /// Logitech device with stable identifiers the name is dropped, because a
    /// receiver and a direct connection may report it under different names.
    /// Other vendors keep it: generic devices may share a product ID and a
    /// fixed serial number and differ only by name.
    var condition: DeviceMatcher {
        var condition = self
        if vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
           productID != nil,
           serialNumber != nil {
            condition.productName = nil
        }
        return condition
    }

    /// Matches the physical device or any logical device it currently routes to.
    func match(with device: Device) -> Bool {
        if isSatisfied(by: DeviceMatcher(of: device)) {
            return true
        }

        return DeviceManager.shared.pairedReceiverDevices(for: device).contains { identity in
            DeviceMatcher(of: device, logicalDevice: identity).map(isSatisfied(by:)) ?? false
        }
    }

    func match(with matcher: DeviceMatcher) -> Bool {
        isSatisfied(by: matcher)
    }

    func isSatisfied(by candidate: DeviceMatcher) -> Bool {
        func matchValue<T: Equatable>(_ destination: T?, _ source: T?) -> Bool {
            destination == nil || source == destination
        }

        guard matchValue(vendorID, candidate.vendorID),
              matchValue(productID, candidate.productID),
              matchValue(productName, candidate.productName),
              matchValue(serialNumber, candidate.serialNumber)
        else {
            return false
        }

        if let category {
            guard let candidateCategory = candidate.category,
                  category.contains(where: { candidateCategory.contains($0) })
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
