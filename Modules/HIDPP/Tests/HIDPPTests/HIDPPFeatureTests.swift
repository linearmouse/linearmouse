// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import HIDPP
import XCTest

final class HIDPPFeatureTests: XCTestCase {
    func testParsesExplicitAndRangeEncodedDPIList() {
        XCTAssertEqual(
            AdjustableDPI.parseSupportedDPI([
                0x03, 0x20, // 800
                0xE0, 0x64, // Range step 100.
                0x04, 0xB0, // Through 1200.
                0x00, 0x00
            ]),
            [800, 900, 1000, 1100, 1200]
        )
    }

    func testReadsAndWritesNearestSupportedDPI() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            switch [UInt8](report)[3] {
            case 0x28:
                return Data([0x11, 0xFF, 0x22, 0x28, 0x00, 0x03, 0x20, 0x00, 0x00])
            case 0x38:
                return Data([0x11, 0xFF, 0x22, 0x38, 0x00, 0x00, 0x00])
            default:
                return nil
            }
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let dpi = AdjustableDPI(
            transport: transport,
            featureIndex: 0x22,
            supportedDPI: [400, 800, 1200]
        )

        XCTAssertEqual(dpi.currentDPI(), 800)
        XCTAssertEqual(dpi.setDPI(760), 800)
        let report = try XCTUnwrap(device.reports.last)
        XCTAssertEqual(Array(report.prefix(7)), [0x11, 0xFF, 0x22, 0x38, 0x00, 0x03, 0x20])
        XCTAssertEqual(device.singleTransactionRequestCount, 1)
    }

    func testAdjustableDPIExposesResolvedReceiverSlot() throws {
        let device = MockHIDPPDevice()
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: 3))
        let dpi = AdjustableDPI(
            transport: transport,
            featureIndex: 0x22,
            supportedDPI: [800]
        )

        XCTAssertEqual(dpi.receiverSlot, 3)
    }

    func testPreservesWheelModeBitsWhenEnablingHighResolutionMode() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            switch [UInt8](report)[3] {
            case 0x18:
                return Data([0x11, 0xFF, 0x1E, 0x18, 0x04, 0x00, 0x00])
            case 0x28:
                return Data([0x11, 0xFF, 0x1E, 0x28, 0x06, 0x00, 0x00])
            default:
                return nil
            }
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let wheel = HiResWheel(transport: transport, featureIndex: 0x1E)

        XCTAssertEqual(
            wheel.applyHighResolutionWheelEnabled(true),
            .init(previousEnabled: false, appliedEnabled: true)
        )
        let report = try XCTUnwrap(device.reports.last)
        XCTAssertEqual([UInt8](report)[4], 0x06)
    }
}
