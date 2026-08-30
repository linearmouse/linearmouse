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

    func testExactDPIRestoreDoesNotUseAPartialSupportedList() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            Data([0x11, 0xFF, 0x22, [UInt8](report)[3], 0x00, 0x00, 0x00])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let dpi = AdjustableDPI(
            transport: transport,
            featureIndex: 0x22,
            supportedDPI: [400, 800]
        )

        XCTAssertEqual(dpi.setDPIExactly(8000) { true }, 8000)
        let report = try XCTUnwrap(device.reports.last)
        XCTAssertEqual(Array(report.prefix(7)), [0x11, 0xFF, 0x22, 0x38, 0x00, 0x1F, 0x40])
    }

    func testSupportedDPIListIsIncompleteWhenASecondPageFails() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes[3] == 0x18, bytes[6] == 0 else {
                return nil
            }
            return Data([0x11, 0xFF, 0x22, 0x18, 0x00, 0x03, 0x20])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        XCTAssertEqual(
            AdjustableDPI.loadSupportedDPI(
                transport: transport,
                featureIndex: 0x22,
                deadline: nil
            ) { true },
            .incomplete
        )
        XCTAssertEqual(device.reports.count, 2)
    }

    func testNormalDPIControllerRejectsAnIncompleteCapabilityList() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes[3] == 0x18, bytes[6] == 0 else {
                return nil
            }
            return Data([0x11, 0xFF, 0x22, 0x18, 0x00, 0x03, 0x20])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        XCTAssertNil(AdjustableDPI(
            transport: transport,
            featureIndex: 0x22,
            deadline: nil
        ) { true })
        XCTAssertEqual(device.reports.count, 2)
    }

    func testCurrentDPIReadsTheCurrentFieldWithoutSubstitutingTheDefault() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { _ in
            Data([0x11, 0xFF, 0x22, 0x28, 0x00, 0x01, 0x04, 0x03, 0xE8])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let dpi = AdjustableDPI(
            transport: transport,
            featureIndex: 0x22,
            supportedDPI: [1000]
        )

        XCTAssertEqual(dpi.currentDPI(), 260)
    }

    func testStrictDPIReadingRejectsAnInvalidRawCurrentValue() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { _ in
            Data([0x11, 0xFF, 0x22, 0x28, 0x00, 0x00, 0x00, 0x03, 0xE8])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let dpi = AdjustableDPI(
            transport: transport,
            featureIndex: 0x22,
            supportedDPI: [1000]
        )

        XCTAssertNil(dpi.currentDPI())
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
