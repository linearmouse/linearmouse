// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import PointerKit
import XCTest

final class VendorSpecificDeviceMetadataTests: XCTestCase {
    func testMatcherMatchesVendorAndTransport() {
        let matcher = VendorSpecificDeviceMatcher(
            vendorID: 0x046D,
            productIDs: [0xB015],
            transports: ["Bluetooth Low Energy"]
        )

        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: "Bluetooth Low Energy"
        )

        XCTAssertTrue(matcher.matches(device: device))
    }

    func testMatcherRejectsUnknownTransport() {
        let matcher = VendorSpecificDeviceMatcher(
            vendorID: 0x046D,
            productIDs: nil,
            transports: ["USB"]
        )

        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: "Bluetooth Low Energy"
        )

        XCTAssertFalse(matcher.matches(device: device))
    }

    func testLogitechProviderMatchesLogitechDeviceShape() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: "Bluetooth Low Energy",
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        XCTAssertTrue(provider.matches(device: device))
    }

    func testReadConnectedLogitechDeviceMetadata() throws {
        let manager = PointerDeviceManager()
        manager.startObservation()
        defer { manager.stopObservation() }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, manager.devices.isEmpty {
            CFRunLoopRunInMode(.defaultMode, 0.1, true)
        }

        let logitechDevices = manager.devices.filter { $0.vendorID == 0x046D }
        guard let device = logitechDevices.first else {
            throw XCTSkip("No connected Logitech pointer device found")
        }

        let metadata = VendorSpecificDeviceMetadataRegistry.metadata(for: device)

        XCTAssertNotNil(metadata?.name, "Expected Logitech HID++ device name")
        XCTAssertNotNil(metadata?.batteryLevel, "Expected Logitech HID++ battery level")

        if let metadata {
            print(
                "Logitech metadata name=\(metadata.name ?? "(nil)") battery=\(metadata.batteryLevel.map(String.init) ?? "(nil)")"
            )
        }
    }
}

private struct MockVendorSpecificDeviceContext: VendorSpecificDeviceContext {
    var vendorID: Int?
    var productID: Int?
    var product: String?
    var name: String
    var transport: String?
    var locationID: Int?
    var primaryUsagePage: Int?
    var primaryUsage: Int?
    var maxInputReportSize: Int?
    var maxOutputReportSize: Int?
    var maxFeatureReportSize: Int?

    init(
        vendorID: Int?,
        productID: Int?,
        product: String? = nil,
        name: String = "Mock Device",
        transport: String?,
        locationID: Int? = nil,
        primaryUsagePage: Int? = nil,
        primaryUsage: Int? = nil,
        maxInputReportSize: Int? = 20,
        maxOutputReportSize: Int? = 20,
        maxFeatureReportSize: Int? = 20
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.product = product
        self.name = name
        self.transport = transport
        self.locationID = locationID
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
        self.maxInputReportSize = maxInputReportSize
        self.maxOutputReportSize = maxOutputReportSize
        self.maxFeatureReportSize = maxFeatureReportSize
    }

    func performSynchronousOutputReportRequest(
        _: Data,
        timeout _: TimeInterval,
        matching _: @escaping (Data) -> Bool
    ) -> Data? {
        nil
    }
}
