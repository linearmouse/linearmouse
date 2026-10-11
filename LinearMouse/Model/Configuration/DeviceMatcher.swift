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

/// The identities one physical device can be matched under.
///
/// A pointing device reached through a monitored Logitech receiver is presented
/// by macOS as the receiver, so its vendor ID, product ID, name and serial are
/// the receiver's. Once the receiver route resolves the paired device, the
/// device is matched as that logical device, which is the same identity it has
/// over Bluetooth. The physical identity is kept as a fallback so schemes
/// written against the receiver keep applying.
struct DeviceMatchCandidates: Equatable {
    /// The identity new schemes are written against.
    let primary: DeviceMatcher
    /// The raw HID identity, present only when it differs from `primary`.
    let fallback: DeviceMatcher?

    var all: [DeviceMatcher] {
        [primary] + (fallback.map { [$0] } ?? [])
    }

    init(physical: DeviceMatcher, logicalIdentity: ReceiverLogicalDeviceIdentity?) {
        guard let logicalIdentity,
              logicalIdentity.productID != nil || logicalIdentity.serialNumber != nil
        else {
            primary = physical
            fallback = nil
            return
        }

        primary = DeviceMatcher(
            vendorID: physical.vendorID,
            productID: logicalIdentity.productID,
            productName: logicalIdentity.name,
            serialNumber: logicalIdentity.serialNumber,
            category: physical.category
        )
        fallback = physical
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

    /// The identity a scheme is written against for `device`.
    init(of device: Device) {
        self = device.matchCandidates.primary
    }

    /// The identity macOS reports for `device`, before any receiver route is
    /// taken into account.
    static func physical(of device: Device) -> DeviceMatcher {
        DeviceMatcher(
            vendorID: device.vendorID,
            productID: device.productID,
            productName: device.productName,
            serialNumber: device.serialNumber,
            category: [Category(from: device.category)]
        )
    }

    func match(with device: Device) -> Bool {
        device.matchCandidates.all.contains { isSatisfied(by: $0) }
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
