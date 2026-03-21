// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ReceiverPacketParserTests: XCTestCase {
    func testParsesMouseActivitySlotFromDJShortReport() {
        let report = Data([0x20, 0x03, 0x02, 0x00, 0x00, 0x00, 0x00])

        XCTAssertEqual(ReceiverPacketParser.activePointingSlot(from: report), 0x03)
    }

    func testParsesKeyboardMouseActivitySlot() {
        let report = Data([0x21, 0x02, 0x05, 0x00, 0x00, 0x00, 0x00])

        XCTAssertEqual(ReceiverPacketParser.activePointingSlot(from: report), 0x02)
    }

    func testRejectsNonPointingDJPacket() {
        let report = Data([0x20, 0x02, 0x01, 0x00, 0x00, 0x00, 0x00])

        XCTAssertNil(ReceiverPacketParser.activePointingSlot(from: report))
    }

    func testRejectsNonDJPacket() {
        let report = Data([0x10, 0x02, 0x41, 0x00, 0x00, 0x00, 0x00])

        XCTAssertNil(ReceiverPacketParser.activePointingSlot(from: report))
    }

    func testLogicalDeviceIdentityEqualityIgnoresBatteryAndNameChanges() {
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
            kind: .mouse,
            name: "Mouse B",
            serialNumber: "BBBB",
            productID: 0x5678,
            batteryLevel: 80
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
    }
}
