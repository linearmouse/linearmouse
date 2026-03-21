// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
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

    func testReceiverLogicalDeviceIdentityEqualityUsesReceiverLocationAndSlot() {
        let lhs = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: 50
        )
        let rhs = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .trackball,
            name: "Mouse B",
            serialNumber: "BBBB",
            productID: 0x5678,
            batteryLevel: 80
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
    }

    func testConnectedBatteryDeviceDirectIdentityPrefersSerialNumber() {
        let identity = ConnectedBatteryDeviceInfo.directIdentity(
            vendorID: 0x046D,
            productID: 0x405E,
            serialNumber: "ABC123",
            locationID: 0x1000,
            transport: "USB",
            fallbackName: "Mouse"
        )

        XCTAssertEqual(identity, "serial|1133|16478|ABC123")
    }

    func testConnectedBatteryDeviceDirectIdentityFallsBackToLocation() {
        let identity = ConnectedBatteryDeviceInfo.directIdentity(
            vendorID: 0x046D,
            productID: 0x405E,
            serialNumber: nil,
            locationID: 0x2000,
            transport: "USB",
            fallbackName: "Mouse"
        )

        XCTAssertEqual(identity, "location|1133|16478|8192")
    }

    func testConnectedBatteryDeviceReceiverIdentityUsesReceiverAndSlot() {
        XCTAssertEqual(
            ConnectedBatteryDeviceInfo.receiverIdentity(receiverLocationID: 0x1234, slot: 2),
            "receiver|4660|2"
        )
    }

    func testVendorSpecificDeviceMetadataSupportsEquality() {
        XCTAssertEqual(
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 50),
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 50)
        )
        XCTAssertNotEqual(
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 50),
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 80)
        )
    }

    func testDeviceManagerDisplayNameUsesSinglePairedDeviceName() {
        let identities = [
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 1,
                kind: .mouse,
                name: "M720 Triathlon",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 50
            )
        ]

        XCTAssertEqual(
            DeviceManager.displayName(baseName: "USB Receiver", pairedDevices: identities),
            "USB Receiver (M720 Triathlon)"
        )
    }

    func testDeviceManagerDisplayNameUsesDeviceCountForMultiplePairedDevices() {
        let identities = [
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 1,
                kind: .mouse,
                name: "Mouse A",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 50
            ),
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 2,
                kind: .trackball,
                name: "Mouse B",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 80
            )
        ]

        XCTAssertEqual(
            DeviceManager.displayName(baseName: "USB Receiver", pairedDevices: identities),
            "USB Receiver (2 devices)"
        )
    }
}

private struct MockVendorSpecificDeviceContext: VendorSpecificDeviceContext {
    var vendorID: Int?
    var productID: Int?
    var product: String?
    var name: String
    var serialNumber: String?
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
        serialNumber: String? = nil,
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
        self.serialNumber = serialNumber
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
