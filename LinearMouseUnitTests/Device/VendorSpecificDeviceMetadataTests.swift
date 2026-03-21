// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
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

    func testInspectConnectedLogitechPointerDevices() throws {
        let manager = PointerDeviceManager()
        manager.startObservation()
        defer { manager.stopObservation() }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, manager.devices.isEmpty {
            CFRunLoopRunInMode(.defaultMode, 0.1, true)
        }

        let logitechDevices = manager.devices.filter { $0.vendorID == 0x046D }
        guard !logitechDevices.isEmpty else {
            throw XCTSkip("No connected Logitech pointer device found")
        }

        for device in logitechDevices {
            let metadata = VendorSpecificDeviceMetadataRegistry.metadata(for: device)
            print(
                "PointerDevice product=\(device.product ?? "(nil)") name=\(device.name) transport=\(device.transport ?? "(nil)") vid=\(device.vendorIDString) pid=\(device.productIDString) metadataName=\(metadata?.name ?? "(nil)") metadataBattery=\(metadata?.batteryLevel.map(String.init) ?? "(nil)")"
            )

            if device.transport == "USB" {
                let provider = LogitechHIDPPDeviceMetadataProvider()
                let identities = provider.receiverPointingDeviceIdentities(for: device)
                print(
                    "Receiver identities=\(identities.map { "slot=\($0.slot) name=\($0.name) battery=\($0.batteryLevel.map(String.init) ?? "(nil)")" })"
                )
            }
        }
    }

    func testReceiverMonitorDiscoversLogicalPointingDevices() throws {
        let pointerManager = PointerDeviceManager()
        pointerManager.startObservation()
        defer { pointerManager.stopObservation() }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, pointerManager.devices.isEmpty {
            CFRunLoopRunInMode(.defaultMode, 0.1, true)
        }

        let receiverPointerDevices = pointerManager.devices.filter {
            $0.vendorID == 0x046D && $0.transport == "USB" && ($0.product ?? $0.name).contains("Receiver")
        }
        guard let receiverPointerDevice = receiverPointerDevices.first else {
            throw XCTSkip("No connected Logitech receiver pointer device found")
        }

        let deviceManager = DeviceManager()
        let device = Device(deviceManager, receiverPointerDevice)
        let monitor = ReceiverMonitor()
        let expectation = expectation(description: "discover receiver logical devices")

        monitor.onPointingDevicesChanged = { _, identities in
            guard !identities.isEmpty else {
                return
            }

            print(
                "Receiver monitor identities=\(identities.map { "slot=\($0.slot) name=\($0.name) battery=\($0.batteryLevel.map(String.init) ?? "(nil)")" })"
            )
            expectation.fulfill()
        }

        monitor.startMonitoring(device: device)
        wait(for: [expectation], timeout: 5)
        monitor.stopMonitoring(device: device)
    }

    func testDeviceManagerPublishesReceiverPairedDeviceIdentities() {
        let deviceManager = DeviceManager.shared
        deviceManager.start()
        defer { deviceManager.stop() }

        let expectation = expectation(description: "receiver paired device identities published")
        var cancellable: AnyCancellable?

        cancellable = deviceManager.$receiverPairedDeviceIdentities.sink { identitiesByLocation in
            guard let identities = identitiesByLocation.values.first(where: { !$0.isEmpty }) else {
                return
            }

            let summary = identities.map {
                "slot=\($0.slot) name=\($0.name) battery=\($0.batteryLevel.map(String.init) ?? "(nil)")"
            }
            print("Published paired identities=\(summary)")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
        _ = cancellable

        let devices = deviceManager.devices
        XCTAssertTrue(devices.contains { ($0.productName ?? $0.name).contains("Receiver") && ($0.vendorID == 0x046D) })
        XCTAssertFalse(devices.contains(where: \.isLogicalDevice))
        XCTAssertTrue(deviceManager.receiverPairedDeviceIdentities.values.contains { !$0.isEmpty })
    }

    func testInspectPublishedDevices() {
        let deviceManager = DeviceManager.shared
        deviceManager.start()
        defer { deviceManager.stop() }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, deviceManager.devices.isEmpty {
            CFRunLoopRunInMode(.defaultMode, 0.1, true)
        }

        for device in deviceManager.devices {
            print(
                "Published device name=\(device.name) productName=\(device.productName ?? "(nil)") battery=\(device.batteryLevel.map(String.init) ?? "(nil)") logical=\(device.isLogicalDevice) transport=\(device.pointerDevice.transport ?? "(nil)")"
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
