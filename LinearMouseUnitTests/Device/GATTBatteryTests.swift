// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import LinearMouse
import XCTest

final class GATTBatteryTests: XCTestCase {
    func testInitialReadThenSubscriptionAndUnsolicitedUpdates() {
        var state = GATTBatteryState()
        XCTAssertEqual(state.start(canRead: true, canNotify: true), [.read])
        XCTAssertEqual(state.receive(Data([85])), [.subscribe])
        state.notificationStateChanged(enabled: true)
        XCTAssertEqual(state.phase, .listening)
        XCTAssertEqual(state.receive(Data([86])), [])
        XCTAssertEqual(state.level, 86)
        XCTAssertEqual(state.receive(Data([87])), [])
        XCTAssertEqual(state.start(canRead: true, canNotify: true), [])
        XCTAssertEqual(state.level, 87)
    }

    func testReadFailureStillAllowsNotificationSubscription() {
        var state = GATTBatteryState()
        XCTAssertEqual(state.start(canRead: true, canNotify: true), [.read])
        XCTAssertEqual(state.receive(nil), [.subscribe])
        state.notificationStateChanged(enabled: true)
        XCTAssertEqual(state.receive(Data([85])), [])
        XCTAssertEqual(state.level, 85)
    }

    func testNotifyOnlyCharacteristicDoesNotAttemptRead() {
        var state = GATTBatteryState()
        XCTAssertEqual(state.start(canRead: false, canNotify: true), [.subscribe])
        XCTAssertEqual(state.receive(Data([85])), [])
        XCTAssertEqual(state.level, 85)
    }

    func testReadOnlyCharacteristicIsNotPolled() {
        var state = GATTBatteryState()
        XCTAssertEqual(state.start(canRead: true, canNotify: false), [.read])
        XCTAssertEqual(state.receive(Data([85])), [])
        XCTAssertEqual(state.phase, .readOnly)
        XCTAssertEqual(state.start(canRead: true, canNotify: false), [])
    }

    func testSubscriptionFailureKeepsInitialValue() {
        var state = GATTBatteryState()
        _ = state.start(canRead: true, canNotify: true)
        _ = state.receive(Data([85]))
        state.notificationStateChanged(enabled: false)
        XCTAssertEqual(state.phase, .readOnly)
        XCTAssertEqual(state.level, 85)
    }

    func testInvalidValuesDoNotEraseLastReadingAndZeroIsValid() {
        var state = GATTBatteryState()
        _ = state.start(canRead: true, canNotify: true)
        _ = state.receive(Data([85]))
        for data in [Data(), Data([255]), Data([85, 0])] {
            _ = state.receive(data)
            XCTAssertEqual(state.level, 85)
        }
        _ = state.receive(Data([0]))
        XCTAssertEqual(state.level, 0)
    }

    func testStopRejectsLateReadsAndReconnectStartsFresh() {
        var state = GATTBatteryState()
        _ = state.start(canRead: true, canNotify: true)
        state.stop()
        XCTAssertEqual(state.receive(Data([85])), [])
        XCTAssertNil(state.level)
        XCTAssertEqual(state.phase, .stopped)
        state = GATTBatteryState()
        XCTAssertEqual(state.start(canRead: true, canNotify: true), [.read])
    }

    func testSerialAndPnPIDMatchTheTestedMouse() {
        var peer = GATTBatteryIdentity(id: UUID(), serialNumber: "TEST1234")
        peer.setPnPID(Data([2, 0x6D, 0x04, 0x35, 0xB0, 9, 0]))
        XCTAssertEqual(peer.vendorID, 1133)
        XCTAssertEqual(peer.productID, 45_109)
        XCTAssertEqual(match(peer, targets: [target(serial: "TEST1234")]), "mouse")
    }

    func testSameNameIsNotUsedToMatchDifferentDevices() {
        let peer = GATTBatteryIdentity(id: UUID(), serialNumber: "other")
        XCTAssertNil(match(peer, targets: [target(serial: "TEST1234")]))
    }

    func testDuplicateSerialAndConflictingProductAreRejected() {
        let peer = GATTBatteryIdentity(id: UUID(), serialNumber: "TEST1234", vendorID: 1133, productID: 45_109)
        let duplicate = GATTBatteryIdentity(id: UUID(), serialNumber: "TEST1234")
        XCTAssertNil(GATTBatteryIdentity.matchedTarget(
            for: peer,
            peers: [peer, duplicate],
            targets: [target(serial: "TEST1234")],
            discoveryComplete: true
        ))
        XCTAssertNil(match(peer, targets: [target(serial: "TEST1234", product: 1234)]))
    }

    func testPnPFallbackRequiresCompletedAndUnambiguousDiscovery() {
        let peer = GATTBatteryIdentity(id: UUID(), vendorID: 1133, productID: 45_109)
        XCTAssertNil(match(peer, targets: [target()], complete: false))
        XCTAssertEqual(match(peer, targets: [target()]), "mouse")
        XCTAssertNil(match(peer, targets: [target(), target(id: "second")]))
        let unknown = GATTBatteryIdentity(id: UUID())
        XCTAssertNil(GATTBatteryIdentity.matchedTarget(
            for: peer,
            peers: [peer, unknown],
            targets: [target()],
            discoveryComplete: true
        ))
    }

    func testBluetoothCompanyIDIsNotTreatedAsUSBVendorID() {
        var peer = GATTBatteryIdentity(id: UUID())
        peer.setPnPID(Data([1, 0x6D, 0x04, 0x35, 0xB0, 9, 0]))
        XCTAssertNil(peer.vendorID)
        XCTAssertNil(match(peer, targets: [target()]))
    }

    private func target(id: String = "mouse", serial: String? = nil, product: Int = 45_109) -> GATTBatteryTarget {
        GATTBatteryTarget(
            id: id,
            generation: 1,
            name: "Mouse",
            serialNumber: serial,
            vendorID: 1133,
            productID: product
        )
    }

    private func match(_ peer: GATTBatteryIdentity, targets: [GATTBatteryTarget], complete: Bool = true) -> String? {
        GATTBatteryIdentity.matchedTarget(for: peer, peers: [peer], targets: targets, discoveryComplete: complete)
    }
}
