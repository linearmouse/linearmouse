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
        XCTAssertEqual(controller?.setDPI(1500), 1600)
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
}
