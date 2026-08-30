// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import HIDPP
@testable import LinearMouse
import PointerKit
import XCTest

/// Covers HID++ Hi-Res Wheel feature encoding, discovery, and transport behavior.
final class HiResWheelTests: XCTestCase {
    func testReadsAndWritesHighResolutionWheelMode() {
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
                guard bytes[4] == 0x21, bytes[5] == 0x21 else {
                    return nil
                }
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x1E])
            case (0x1E, 0x08):
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x08, payload: [0x08, 0x0C])
            case (0x1E, 0x18):
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x18, payload: [0x04, 0x00])
            case (0x1E, 0x28):
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x28, payload: [])
            default:
                return nil
            }
        }

        let controller = HiResWheel(
            device: device,
            receiverSlot: nil
        ) { true }

        XCTAssertEqual(controller?.capabilities(), .init(multiplier: 8, flags: 0x0C))
        XCTAssertEqual(controller?.isHighResolutionWheelEnabled(), false)
        XCTAssertEqual(controller?.setHighResolutionWheelEnabled(true), true)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(5)) },
            Optional([0x11, 0xFF, 0x1E, 0x28, 0x06] as [UInt8])
        )
    }

    func testSkipsWritingWhenHighResolutionWheelModeAlreadyMatches() {
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
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x1E])
            case (0x1E, 0x18):
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x18, payload: [0x06, 0x00])
            default:
                return nil
            }
        }

        let controller = HiResWheel(
            device: device,
            receiverSlot: nil
        ) { true }

        XCTAssertEqual(controller?.setHighResolutionWheelEnabled(true), true)
        XCTAssertEqual(device.outputReportRequestCount, 2)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(4)) },
            Optional([0x11, 0xFF, 0x1E, 0x18] as [UInt8])
        )
    }

    func testApplyReturnsPreviousModeUsingOneReadAndOneWrite() {
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
                return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x1E])
            case (0x1E, 0x18):
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x18, payload: [0x04, 0x00])
            case (0x1E, 0x28):
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x28, payload: [])
            default:
                return nil
            }
        }

        let controller = HiResWheel(
            device: device,
            receiverSlot: nil
        ) { true }
        let requestCount = device.outputReportRequestCount

        XCTAssertEqual(
            controller?.applyHighResolutionWheelEnabled(true),
            .init(previousEnabled: false, appliedEnabled: true)
        )
        XCTAssertEqual(device.outputReportRequestCount, requestCount + 2)
    }

    func testWriteLosesAdmissionAfterModeRead() throws {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        var admitted = true
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes[2] == 0x1E, bytes[3] == 0x18 else {
                return nil
            }
            admitted = false
            return Self.hidppLongReply(
                featureIndex: 0x1E,
                address: 0x18,
                payload: [0x04, 0x00]
            )
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let controller = HiResWheel(transport: transport, featureIndex: 0x1E)

        XCTAssertNil(controller.setHighResolutionWheelEnabled(
            true
        ) { admitted })
        XCTAssertEqual(device.sentReports.count, 1)
        XCTAssertEqual([UInt8](device.sentReports[0])[3], 0x18)
    }

    func testRejectsDeviceWithoutHiresWheelFeature() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 6, bytes[2] == 0x00, bytes[3] == 0x08 else {
                return nil
            }

            return Self.hidppLongReply(featureIndex: 0x00, address: 0x08, payload: [0x00])
        }

        XCTAssertNil(HiResWheel(
            device: device,
            receiverSlot: nil
        ) { true })
    }

    func testReadsAndWritesHighResolutionWheelModeThroughReceiverSlot() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4 else {
                return nil
            }

            switch (bytes[2], bytes[3]) {
            case (0x1E, 0x08):
                return Self.hidppLongReply(
                    deviceIndex: bytes[1],
                    featureIndex: 0x1E,
                    address: 0x08,
                    payload: [0x08, 0x0C]
                )
            case (0x1E, 0x18):
                return Self.hidppLongReply(
                    deviceIndex: bytes[1],
                    featureIndex: 0x1E,
                    address: 0x18,
                    payload: [0x04, 0x00]
                )
            case (0x1E, 0x28):
                return Self.hidppLongReply(
                    deviceIndex: bytes[1],
                    featureIndex: 0x1E,
                    address: 0x28,
                    payload: []
                )
            default:
                return nil
            }
        }

        let transport = HIDPPTransport(device: device, deviceIndex: 2)
        let controller = transport.map {
            HiResWheel(transport: $0, featureIndex: 0x1E)
        }

        XCTAssertEqual(controller?.capabilities(), .init(multiplier: 8, flags: 0x0C))
        XCTAssertEqual(controller?.isHighResolutionWheelEnabled(), false)
        XCTAssertEqual(controller?.setHighResolutionWheelEnabled(true), true)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(5)) },
            Optional([0x11, 0x02, 0x1E, 0x28, 0x06] as [UInt8])
        )
    }

    func testRejectsUnsupportedTransport() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: "SPI",
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        XCTAssertNil(HiResWheel(
            device: device,
            receiverSlot: nil
        ) { true })
        XCTAssertEqual(device.outputReportRequestCount, 0)
    }

    private static func hidppLongReply(
        deviceIndex: UInt8 = 0xFF,
        featureIndex: UInt8,
        address: UInt8,
        payload: [UInt8]
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x11
        bytes[1] = deviceIndex
        bytes[2] = featureIndex
        bytes[3] = address
        for (index, byte) in payload.enumerated() where index + 4 < bytes.count {
            bytes[index + 4] = byte
        }
        return Data(bytes)
    }
}
