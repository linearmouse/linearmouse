// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
@testable import LinearMouse
import PointerKit
import XCTest

final class HIDPPBatteryObservationTests: XCTestCase {
    func testInitialReadThenChargingNotificationsWithoutPolling() throws {
        let device = makeDevice()
        var updates = [HIDPPBatteryObservation.Update]()
        let observer = HIDPPBatteryObservation { updates.append($0) }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        observer.readInitial(using: transport)
        let requestCount = device.outputReportRequestCount
        XCTAssertEqual(updates.last?.reading.level, 20)

        observer.receive(notification(level: 21, status: 1))
        observer.receive(notification(level: 65, status: 1))
        observer.receive(notification(level: 65, status: 0))
        observer.readInitial(using: transport)

        XCTAssertEqual(updates.map(\.reading.level), [20, 21, 65, 65])
        XCTAssertEqual(updates.last?.reading.chargeState, .discharging)
        XCTAssertEqual(updates.map(\.sequence), [1, 2, 3, 4])
        XCTAssertEqual(device.outputReportRequestCount, requestCount)
    }

    func testNotificationDuringInitialReadWinsOverOlderResponse() throws {
        let device = makeDevice()
        var levels = [Int?]()
        let observer = HIDPPBatteryObservation { levels.append($0.reading.level) }
        device.responseProvider = { report in
            if report[2] == 7, report[3] >> 4 == 1 {
                observer.receive(self.notification(level: 65, status: 1))
            }
            return self.reply(report)
        }
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        XCTAssertEqual(levels, [65])
    }

    func testNotificationBeforeFeatureDiscoveryIsRetained() throws {
        let device = makeDevice()
        var levels = [Int?]()
        let observer = HIDPPBatteryObservation { levels.append($0.reading.level) }
        observer.receive(notification(level: 65, status: 1))
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        XCTAssertEqual(levels, [65])
    }

    func testControlReportsCannotEvictBatteryNotificationDuringDiscovery() throws {
        let device = makeDevice()
        var levels = [Int?]()
        let observer = HIDPPBatteryObservation { levels.append($0.reading.level) }
        observer.receive(notification(level: 65, status: 1))
        for _ in 0 ..< 100 {
            observer.receive(notification(level: 80, status: 1, feature: 8))
        }
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        XCTAssertEqual(levels, [65])
    }

    func testReceiverSlotFeatureAndSoftwareIDAreValidated() throws {
        let device = makeDevice()
        var levels = [Int?]()
        let observer = HIDPPBatteryObservation(receiverSlot: 2) { levels.append($0.reading.level) }
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: 2)))
        observer.receive(notification(level: 80, status: 1, slot: 1))
        observer.receive(notification(level: 80, status: 1, slot: 2, feature: 8))
        observer.receive(notification(level: 80, status: 1, slot: 2, address: 8))
        observer.receive(Data([0x11, 2, 7, 0, 80]))
        XCTAssertEqual(levels, [20])
        observer.receive(notification(level: 65, status: 1, slot: 2))
        XCTAssertEqual(levels, [20, 65])
    }

    func testStoppedConnectionIgnoresReportsAndLateInitialRead() throws {
        let device = makeDevice()
        var levels = [Int?]()
        let observer = HIDPPBatteryObservation { levels.append($0.reading.level) }
        device.responseProvider = { report in
            if report[2] == 7, report[3] >> 4 == 1 {
                observer.stop()
            }
            return self.reply(report)
        }
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        observer.receive(notification(level: 65, status: 1))
        XCTAssertTrue(levels.isEmpty)
    }

    func testReconnectUsesNewFeatureIndexAndReadsAgain() throws {
        let device = makeDevice()
        var levels = [Int?]()
        let old = HIDPPBatteryObservation { levels.append($0.reading.level) }
        try old.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        old.stop()
        device.responseProvider = { self.reply($0, index: 9) }
        let new = HIDPPBatteryObservation { levels.append($0.reading.level) }
        try new.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        old.receive(notification(level: 80, status: 1))
        new.receive(notification(level: 80, status: 1))
        new.receive(notification(level: 65, status: 1, feature: 9))
        XCTAssertEqual(levels, [20, 20, 65])
    }

    func testUnsupportedDeviceIsNotPeriodicallyQueried() throws {
        let device = makeDevice()
        device.responseProvider = { report in
            var response = report
            response[4] = 0
            return response
        }
        let observer = HIDPPBatteryObservation { _ in XCTFail("No battery feature") }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        observer.readInitial(using: transport)
        let requestCount = device.outputReportRequestCount
        observer.readInitial(using: transport)
        observer.receive(notification(level: 65, status: 1))
        XCTAssertEqual(device.outputReportRequestCount, requestCount)
    }

    func testFeatureIndexIsDiscoveredRatherThanAssumedToBeLow() throws {
        let device = makeDevice()
        device.responseProvider = { self.reply($0, index: 0x90) }
        var levels = [Int?]()
        let observer = HIDPPBatteryObservation { levels.append($0.reading.level) }
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        observer.receive(notification(level: 65, status: 1, feature: 0x90))
        XCTAssertEqual(levels, [20, 65])
    }

    func testBatteryStatusUnknownPercentDoesNotBecomeZero() {
        let feature = HIDPPBatteryObservation.Feature(id: .batteryStatus, index: 7)
        XCTAssertEqual(feature.decode([0, 0, 1])?.chargeState, .charging)
        XCTAssertNil(feature.decode([0, 0, 1])?.level)
        XCTAssertEqual(feature.decode([100, 0, 3])?.chargeState, .full)
        XCTAssertNil(feature.decode([255, 0, 0])?.level)
    }

    func testUnifiedBatteryWithoutPercentageUsesItsDiscreteLevel() {
        let feature = HIDPPBatteryObservation.Feature(id: .unifiedBattery, index: 7, supportsPercentage: false)
        XCTAssertEqual(feature.decode([75, 4, 0, 0])?.level, 50)
        XCTAssertNil(feature.decode([75, 255, 0, 0])?.level)
    }

    func testVoltageAndADCValidateFlagsAndPayload() {
        let voltage = HIDPPBatteryObservation.Feature(id: .batteryVoltage, index: 7)
        XCTAssertEqual(voltage.decode([0x10, 0x68, 0x83])?.chargeState, .full)
        let adc = HIDPPBatteryObservation.Feature(id: .adcMeasurement, index: 7)
        XCTAssertNil(adc.decode([0x10, 0x68, 0]))
        XCTAssertEqual(adc.decode([0x10, 0x68, 3])?.chargeState, .charging)
        XCTAssertNil(adc.decode([0xFF, 0xFF, 3]))
    }

    func testReportObserversBroadcastWithoutConsumingEachOthersReports() {
        let observers = HIDPPReportObservers()
        var battery = 0
        var controls = 0
        let batteryToken = observers.observe { _ in battery += 1 }
        let controlToken = observers.observe { _ in controls += 1 }
        observers.receive(notification(level: 65, status: 1))
        batteryToken.cancel()
        observers.receive(notification(level: 70, status: 1))
        XCTAssertEqual(battery, 1)
        XCTAssertEqual(controls, 2)
        controlToken.cancel()
    }

    func testReceiverDisplayUsesObservedBatteryInsteadOfDiscoveryCache() {
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: 2,
            kind: .mouse,
            name: "Mouse",
            serialNumber: "ABC",
            productID: nil,
            batteryLevel: 20
        )
        let level = ConnectedBatteryDeviceInfo.currentDeviceBatteryLevel(
            pairedDevices: [identity],
            directDeviceIdentity: nil,
            inventory: [.init(id: "receiver|1|2", name: "Mouse", batteryLevel: 65)]
        )
        XCTAssertEqual(level, 65)
    }

    func testBatteryStatusFallbackAcceptsShortNotifications() throws {
        let device = makeDevice()
        device.responseProvider = { report in
            var response = report
            for i in 4 ..< response.count {
                response[i] = 0
            }
            if report[2] == 0 {
                response[4] = report[4] == 0x10 && report[5] == 0 ? 5 : 0
            } else if report[2] == 5 {
                response[4] = 40
                response[6] = 1
            }
            return response
        }
        var levels = [Int?]()
        let observer = HIDPPBatteryObservation { levels.append($0.reading.level) }
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        observer.receive(Data([0x10, 0xFF, 5, 0, 65, 0, 1]))
        XCTAssertEqual(levels, [40, 65])
    }

    func testConcurrentNotificationsAndStop() throws {
        let device = makeDevice()
        let valuesLock = NSLock()
        var sequences = Set<UInt64>()
        var duplicate = false
        let observer = HIDPPBatteryObservation { update in
            valuesLock.withLock {
                if !sequences.insert(update.sequence).inserted {
                    duplicate = true
                }
            }
        }
        try observer.readInitial(using: XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil)))
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for iteration in 0 ..< 200 {
                if worker == 0, iteration == 100 {
                    observer.stop()
                }
                observer.receive(self.notification(level: UInt8(iteration % 100 + 1), status: 1))
            }
        }
        XCTAssertFalse(duplicate)
        XCTAssertFalse(sequences.isEmpty)
        let count = sequences.count
        observer.receive(notification(level: 65, status: 1))
        XCTAssertEqual(sequences.count, count)
    }

    private func makeDevice() -> MockVendorSpecificDeviceContext {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB034,
            transport: PointerDeviceTransportName.bluetoothLowEnergy
        )
        device.responseProvider = { self.reply($0) }
        return device
    }

    private func reply(_ report: Data, index: UInt8 = 7) -> Data {
        var response = report
        for i in 4 ..< response.count {
            response[i] = 0
        }
        if report[2] == 0 {
            response[4] = report[4] == 0x10 && report[5] == 4 ? index : 0
        } else if report[2] == index {
            if report[3] >> 4 == 0 {
                response[5] = 2
            } else {
                response[4] = 20; response[5] = 2
            }
        }
        return response
    }

    private func notification(
        level: UInt8,
        status: UInt8,
        slot: UInt8 = 0xFF,
        feature: UInt8 = 7,
        address: UInt8 = 0
    ) -> Data {
        var data = Data(repeating: 0, count: 20)
        data[0] = 0x11; data[1] = slot; data[2] = feature; data[3] = address
        data[4] = level; data[5] = 4; data[6] = status
        return data
    }
}
