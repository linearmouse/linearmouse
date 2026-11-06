// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import HIDPP
import XCTest

final class SmartShiftTests: XCTestCase {
    func testReadsEnhancedStatusAndCapabilities() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            switch [UInt8](report)[3] {
            case 0x08:
                return Data([0x11, 0xFF, 0x0E, 0x08, 0x01, 0x1E, 0x32, 0x40])
            case 0x18:
                return Data([0x11, 0xFF, 0x0E, 0x18, 0x02, 0x23, 0x4B])
            default:
                return nil
            }
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let smartShift = try XCTUnwrap(SmartShift(
            transport: transport,
            featureIndex: 0x0E,
            variant: .enhanced,
            deadline: nil
        ) { true })

        XCTAssertTrue(smartShift.supportsTunableTorque)
        XCTAssertEqual(smartShift.defaultAutoDisengage, 0x1E)
        XCTAssertEqual(
            smartShift.status(),
            .init(wheelMode: .ratchet, autoDisengage: 35, torque: 75)
        )
    }

    func testWritesEnhancedFieldsWithDoNotChangeSentinels() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { _ in
            Data([0x11, 0x02, 0x0E, 0x28, 0x01, 0x23, 0x4B])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: 2))
        let smartShift = SmartShift(
            transport: transport,
            featureIndex: 0x0E,
            variant: .enhanced,
            supportsTunableTorque: true
        )

        XCTAssertEqual(
            smartShift.apply(.init(wheelMode: .freeSpin, torque: 75)),
            .init(wheelMode: .freeSpin, autoDisengage: 35, torque: 75)
        )
        let report = try XCTUnwrap(device.reports.last)
        XCTAssertEqual(Array(report.prefix(7)), [0x11, 0x02, 0x0E, 0x28, 0x01, 0x00, 0x4B])
        XCTAssertEqual(smartShift.receiverSlot, 2)
    }

    func testStandardFeatureNeverWritesTheDefaultThresholdByte() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            switch [UInt8](report)[3] {
            case 0x08:
                return Data([0x11, 0xFF, 0x0D, 0x08, 0x02, 0x0A, 0x0A])
            case 0x18:
                return Data([0x11, 0xFF, 0x0D, 0x18, 0x02, 0x23, 0x0A])
            default:
                return nil
            }
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let smartShift = try XCTUnwrap(SmartShift(
            transport: transport,
            featureIndex: 0x0D,
            variant: .standard,
            deadline: nil
        ) { true })

        XCTAssertFalse(smartShift.supportsTunableTorque)
        XCTAssertEqual(smartShift.defaultAutoDisengage, 0x0A)
        // The standard status reply's third byte is the default threshold, not torque.
        XCTAssertEqual(smartShift.status(), .init(wheelMode: .ratchet, autoDisengage: 10, torque: nil))
        XCTAssertEqual(
            smartShift.apply(.init(wheelMode: .ratchet, autoDisengage: 35, torque: 75)),
            .init(wheelMode: .ratchet, autoDisengage: 35, torque: nil)
        )
        let report = try XCTUnwrap(device.reports.last)
        XCTAssertEqual(Array(report.prefix(7)), [0x11, 0xFF, 0x0D, 0x18, 0x02, 0x23, 0x00])
    }

    func testRejectsOutOfRangeWritesWithoutSendingThem() throws {
        let device = MockHIDPPDevice()
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let smartShift = SmartShift(
            transport: transport,
            featureIndex: 0x0E,
            variant: .enhanced,
            supportsTunableTorque: true
        )

        XCTAssertNil(smartShift.apply(.init(torque: 0)))
        XCTAssertNil(smartShift.apply(.init(torque: 101)))
        XCTAssertNil(smartShift.apply(.init(autoDisengage: 0)))
        XCTAssertTrue(device.reports.isEmpty)
    }

    func testDropsTorqueWhenTheWheelDoesNotAdvertiseIt() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            switch [UInt8](report)[3] {
            case 0x08:
                return Data([0x11, 0xFF, 0x0E, 0x08, 0x00, 0x1E, 0x32, 0x40])
            case 0x28:
                return Data([0x11, 0xFF, 0x0E, 0x28, 0x02, 0x23, 0x32])
            default:
                return nil
            }
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let smartShift = try XCTUnwrap(SmartShift(
            transport: transport,
            featureIndex: 0x0E,
            variant: .enhanced,
            deadline: nil
        ) { true })

        XCTAssertFalse(smartShift.supportsTunableTorque)
        XCTAssertNotNil(smartShift.apply(.init(autoDisengage: 35, torque: 75)))
        let report = try XCTUnwrap(device.reports.last)
        XCTAssertEqual(Array(report.prefix(7)), [0x11, 0xFF, 0x0E, 0x28, 0x00, 0x23, 0x00])

        // A torque-only change has nothing left to write.
        XCTAssertNil(smartShift.apply(.init(torque: 75)))
        XCTAssertEqual(device.reports.count, 2)
    }

    func testRejectsUnknownStatusValues() {
        XCTAssertNil(SmartShift.parseStatus([0x00, 0x20, 0x32], variant: .enhanced))
        XCTAssertNil(SmartShift.parseStatus([0x03, 0x20, 0x32], variant: .enhanced))
        XCTAssertNil(SmartShift.parseStatus([0x02, 0x00, 0x32], variant: .enhanced))
        XCTAssertNil(SmartShift.parseStatus([0x02, 0x20, 0x65], variant: .enhanced))
        XCTAssertNil(SmartShift.parseStatus([0x02, 0x20], variant: .enhanced))
        XCTAssertEqual(
            SmartShift.parseStatus([0x02, 0xFF, 0x00], variant: .enhanced),
            .init(wheelMode: .ratchet, autoDisengage: SmartShift.permanentRatchet, torque: nil)
        )
    }
}
