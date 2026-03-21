// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

protocol VendorSpecificDeviceContext {
    var vendorID: Int? { get }
    var productID: Int? { get }
    var product: String? { get }
    var name: String { get }
    var serialNumber: String? { get }
    var transport: String? { get }
    var locationID: Int? { get }
    var primaryUsagePage: Int? { get }
    var primaryUsage: Int? { get }
    var maxInputReportSize: Int? { get }
    var maxOutputReportSize: Int? { get }
    var maxFeatureReportSize: Int? { get }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data?
}

struct VendorSpecificDeviceMatcher {
    let vendorID: Int?
    let productIDs: Set<Int>?
    let transports: Set<String>?

    func matches(device: VendorSpecificDeviceContext) -> Bool {
        if let vendorID, device.vendorID != vendorID {
            return false
        }

        if let productIDs {
            guard let productID = device.productID,
                  productIDs.contains(productID) else {
                return false
            }
        }

        if let transports {
            guard let transport = device.transport,
                  transports.contains(transport) else {
                return false
            }
        }

        return true
    }
}

struct VendorSpecificDeviceMetadata: Equatable {
    let name: String?
    let batteryLevel: Int?
}

protocol VendorSpecificDeviceMetadataProvider {
    var matcher: VendorSpecificDeviceMatcher { get }
    func metadata(for device: VendorSpecificDeviceContext) -> VendorSpecificDeviceMetadata?
}

extension VendorSpecificDeviceMetadataProvider {
    func matches(device: VendorSpecificDeviceContext) -> Bool {
        matcher.matches(device: device)
    }
}

enum VendorSpecificDeviceMetadataRegistry {
    static let providers: [VendorSpecificDeviceMetadataProvider] = [
        LogitechHIDPPDeviceMetadataProvider()
    ]

    static func metadata(for device: VendorSpecificDeviceContext) -> VendorSpecificDeviceMetadata? {
        for provider in providers where provider.matches(device: device) {
            if let metadata = provider.metadata(for: device) {
                return metadata
            }
        }

        return nil
    }
}
