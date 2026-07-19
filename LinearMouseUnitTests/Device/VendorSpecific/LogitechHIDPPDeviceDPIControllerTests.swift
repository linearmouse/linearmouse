// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import LinearMouse
import PointerKit
import XCTest

final class LogitechHIDPPDeviceDPIControllerTests: XCTestCase {
    func testParsesExplicitAndRangeEncodedDPIList() {
        XCTAssertEqual(
            LogitechHIDPPDeviceDPIController.parseSupportedDPI([
                0x03, 0x20, // 800
                0xE0, 0x64, // range step 100
                0x04, 0xB0, // through 1200
                0x00, 0x00
            ]),
            [800, 900, 1000, 1100, 1200]
        )
    }

    func testBoltReceiverSlotFallsBackToOnlyDiscoveredPointingDevice() {
        let device = Self.boltReceiver()
        let identities = [Self.receiverIdentity(slot: 2, name: "MX Master 3S")]
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertEqual(
            provider.receiverSlot(for: device, identities: identities),
            2
        )
    }

    func testBoltReceiverSlotUsesSerialMatchWhenMultipleDevicesArePaired() {
        let device = Self.boltReceiver(product: "MX Master 3S", serialNumber: "AB:CD:EF:01")
        let identities = [
            Self.receiverIdentity(slot: 1, name: "MX Master 3S", serialNumber: "12345678", productID: 0xB03E),
            Self.receiverIdentity(slot: 3, name: "MX Master 3S", serialNumber: "ABCDEF01", productID: 0xB034)
        ]
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertEqual(
            provider.receiverSlot(for: device, identities: identities),
            3
        )
    }

    func testBoltReceiverSlotRejectsAmbiguousPairedDevices() {
        let device = Self.boltReceiver()
        let identities = [
            Self.receiverIdentity(slot: 1, name: "MX Ergo S"),
            Self.receiverIdentity(slot: 3, name: "MX Master 3S")
        ]
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlot(for: device, identities: identities))
    }

    func testBoltReceiverSlotRejectsDuplicateProductIDMatches() {
        let device = Self.boltReceiver()
        let identities = [
            Self.receiverIdentity(slot: 1, name: "MX Ergo S", productID: 0xC548),
            Self.receiverIdentity(slot: 3, name: "MX Master 3S", productID: 0xC548)
        ]
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlot(for: device, identities: identities))
    }

    func testBoltReceiverSlotRejectsDuplicateNameMatches() {
        let device = Self.boltReceiver(product: "MX Master 3S")
        let identities = [
            Self.receiverIdentity(slot: 1, name: "MX Master 3S"),
            Self.receiverIdentity(slot: 3, name: "MX Master 3S")
        ]
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlot(for: device, identities: identities))
    }

    func testReadsAndWritesAdjustableDPI() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4 else {
                return nil
            }

            switch (bytes[2], bytes[3]) {
            case (0x00, 0x08):
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x05])
            case (0x05, 0x18):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x18,
                    payload: [0x00, 0x03, 0x20, 0x06, 0x40, 0x00, 0x00]
                )
            case (0x05, 0x28):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x28,
                    payload: [0x00, 0x03, 0x20, 0x06, 0x40]
                )
            case (0x05, 0x38):
                return Self.hidppLongReply(featureIndex: 0x05, address: 0x38, payload: [0x00])
            default:
                return nil
            }
        }

        let controller = LogitechHIDPPDeviceDPIController(device: device)

        XCTAssertEqual(controller?.supportedDPI, [800, 1600])
        XCTAssertEqual(controller?.currentDPI(), 800)
        XCTAssertEqual(controller?.dpiRange, 800 ... 1600)
        XCTAssertEqual(controller?.dpiStep, 800)
        let requestCount = device.outputReportRequestCount
        XCTAssertEqual(controller?.setDPI(1500), 1600)
        XCTAssertEqual(device.outputReportRequestCount, requestCount + 1)
        XCTAssertEqual(device.outputReportRequestOnceCount, 0)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(7)) },
            Optional([0x11, 0xFF, 0x05, 0x38, 0x00, 0x06, 0x40] as [UInt8])
        )
    }

    func testSortsSupportedDPIBeforePublishingRange() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4 else {
                return nil
            }

            switch (bytes[2], bytes[3]) {
            case (0x00, 0x08):
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x05])
            case (0x05, 0x18):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x18,
                    payload: [0x00, 0x06, 0x40, 0x03, 0x20, 0x00, 0x00]
                )
            default:
                return nil
            }
        }

        let controller = LogitechHIDPPDeviceDPIController(device: device)

        XCTAssertEqual(controller?.supportedDPI, [800, 1600])
        XCTAssertEqual(controller?.dpiRange, 800 ... 1600)
        XCTAssertEqual(controller?.dpiStep, 800)
    }

    func testFiltersImplausibleSupportedDPIValues() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4 else {
                return nil
            }

            switch (bytes[2], bytes[3]) {
            case (0x00, 0x08):
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x05])
            case (0x05, 0x18):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x18,
                    payload: [
                        0x00,
                        0x00, 0x01, // 1
                        0x01, 0x04, // 260
                        0x50, 0x00, // 20480
                        0x03, 0xE8, // 1000
                        0x00, 0x00
                    ]
                )
            default:
                return nil
            }
        }

        let controller = LogitechHIDPPDeviceDPIController(device: device)

        XCTAssertEqual(controller?.supportedDPI, [1000])
        XCTAssertEqual(controller?.dpiRange, 1000 ... 1000)
        XCTAssertEqual(controller?.dpiStep, 50)
        XCTAssertEqual(controller?.supportedDPI(nearestTo: 260), 1000)
        XCTAssertEqual(controller?.canRepresentDPI(260), false)
    }

    func testSetDPIFailsWithoutAcknowledgementAndDoesNotReadBack() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        var currentDPI = 800
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4 else {
                return nil
            }

            switch (bytes[2], bytes[3]) {
            case (0x00, 0x08):
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x05])
            case (0x05, 0x18):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x18,
                    payload: [0x00, 0x03, 0x20, 0x06, 0x40, 0x00, 0x00]
                )
            case (0x05, 0x28):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x28,
                    payload: [0x00, UInt8((currentDPI >> 8) & 0xFF), UInt8(currentDPI & 0xFF), 0x00, 0x00]
                )
            case (0x05, 0x38):
                currentDPI = Int(bytes[5]) << 8 | Int(bytes[6])
                return nil
            default:
                return nil
            }
        }

        let controller = LogitechHIDPPDeviceDPIController(device: device)

        let requestCount = device.sentReports.count

        XCTAssertNil(controller?.setDPI(1600))
        XCTAssertEqual(device.sentReports.count, requestCount + 1)
        XCTAssertEqual(device.outputReportRequestOnceCount, 0)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(7)) },
            [0x11, 0xFF, 0x05, 0x38, 0x00, 0x06, 0x40]
        )
    }

    func testSetDPISendsOneShortRequestAndWaitsForAcknowledgement() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        device.responseProvider = { report in
            let bytes = [UInt8](report)
            return Self.hidppShortReply(
                deviceIndex: bytes[1],
                featureIndex: bytes[2],
                address: bytes[3],
                payload: [0x00, 0x06, 0x40]
            )
        }

        let transport = LogitechHIDPPTransport(device: device, deviceIndex: 2)
        let controller = transport.map {
            LogitechHIDPPDeviceDPIController(
                transport: $0,
                featureIndex: 0x05,
                supportedDPI: [800, 1600]
            )
        }

        XCTAssertEqual(controller?.setDPI(1600), 1600)
        XCTAssertEqual(device.outputReportRequestOnceCount, 1)
        XCTAssertEqual(device.outputReportRequestCount, 0)
        XCTAssertEqual(device.sentReports.map(Array.init), [[0x10, 0x02, 0x05, 0x38, 0x00, 0x06, 0x40]])
    }

    func testSetDPIFailsWhenAcknowledgementIsMissing() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        let transport = LogitechHIDPPTransport(device: device, deviceIndex: 2)
        let controller = transport.map {
            LogitechHIDPPDeviceDPIController(
                transport: $0,
                featureIndex: 0x05,
                supportedDPI: [800, 1600]
            )
        }

        XCTAssertNil(controller?.setDPI(1600))
        XCTAssertEqual(device.outputReportRequestOnceCount, 1)
        XCTAssertEqual(device.outputReportRequestCount, 0)
    }

    func testSetDPIFailsWhenAcknowledgementEchoesDifferentDPI() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            return Self.hidppShortReply(
                deviceIndex: bytes[1],
                featureIndex: bytes[2],
                address: bytes[3],
                payload: [0x00, 0x03, 0x20]
            )
        }

        let transport = LogitechHIDPPTransport(device: device, deviceIndex: 2)
        let controller = transport.map {
            LogitechHIDPPDeviceDPIController(
                transport: $0,
                featureIndex: 0x05,
                supportedDPI: [800, 1600]
            )
        }

        XCTAssertNil(controller?.setDPI(1600))
        XCTAssertEqual(device.outputReportRequestOnceCount, 1)
    }

    func testCurrentDPIUsesSupportedDefaultWhenCurrentBytesAreNotSupported() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4 else {
                return nil
            }

            switch (bytes[2], bytes[3]) {
            case (0x00, 0x08):
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x05])
            case (0x05, 0x18):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x18,
                    payload: [0x00, 0x03, 0xE8, 0x06, 0x40, 0x00, 0x00]
                )
            case (0x05, 0x28):
                return Self.hidppLongReply(
                    featureIndex: 0x05,
                    address: 0x28,
                    payload: [0x00, 0x01, 0x04, 0x03, 0xE8]
                )
            default:
                return nil
            }
        }

        let controller = LogitechHIDPPDeviceDPIController(device: device)

        XCTAssertEqual(controller?.currentDPI(), 1000)
    }

    private static func boltReceiver(
        product: String? = nil,
        serialNumber: String? = nil
    ) -> MockVendorSpecificDeviceContext {
        MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            product: product,
            name: product ?? "Logi Bolt Receiver",
            serialNumber: serialNumber,
            transport: PointerDeviceTransportName.usb,
            locationID: 1,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
    }

    private static func receiverIdentity(
        slot: UInt8,
        name: String,
        serialNumber: String? = nil,
        productID: Int? = nil
    ) -> ReceiverLogicalDeviceIdentity {
        ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: slot,
            kind: .mouse,
            name: name,
            serialNumber: serialNumber,
            productID: productID,
            batteryLevel: nil
        )
    }

    private static func hidppLongReply(featureIndex: UInt8, address: UInt8, payload: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x11
        bytes[1] = 0xFF
        bytes[2] = featureIndex
        bytes[3] = address
        for (index, byte) in payload.enumerated() where index + 4 < bytes.count {
            bytes[index + 4] = byte
        }
        return Data(bytes)
    }

    private static func hidppShortReply(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        address: UInt8,
        payload: [UInt8]
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 7)
        bytes[0] = 0x10
        bytes[1] = deviceIndex
        bytes[2] = featureIndex
        bytes[3] = address
        for (index, byte) in payload.prefix(3).enumerated() {
            bytes[index + 4] = byte
        }
        return Data(bytes)
    }
}
