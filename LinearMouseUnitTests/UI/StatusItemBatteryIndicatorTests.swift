// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class StatusItemBatteryIndicatorTests: XCTestCase {
    func testMenuBarBatteryTitleDisabledReturnsNil() {
        XCTAssertNil(StatusItem.menuBarBatteryTitle(currentBatteryLevel: 12, mode: .off))
    }

    func testMenuBarBatteryTitleHiddenAboveThreshold() {
        XCTAssertNil(StatusItem.menuBarBatteryTitle(currentBatteryLevel: 21, mode: .below20))
    }

    func testMenuBarBatteryTitleShownAtThreshold() {
        XCTAssertEqual(StatusItem.menuBarBatteryTitle(currentBatteryLevel: 20, mode: .below20), "20%")
    }

    func testMenuBarBatteryTitleAlwaysShowMode() {
        XCTAssertEqual(StatusItem.menuBarBatteryTitle(currentBatteryLevel: 100, mode: .always), "100%")
    }

    func testCurrentDeviceBatteryLevelUsesLowestReceiverBattery() {
        let pairedDevices = [
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 1,
                kind: .mouse,
                name: "Mouse A",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 60
            ),
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 2,
                kind: .mouse,
                name: "Mouse B",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 15
            )
        ]

        let inventory = [
            ConnectedBatteryDeviceInfo(id: "receiver|1|1", name: "Mouse A", batteryLevel: 60),
            ConnectedBatteryDeviceInfo(id: "receiver|1|2", name: "Mouse B", batteryLevel: 15)
        ]

        XCTAssertEqual(
            ConnectedBatteryDeviceInfo.currentDeviceBatteryLevel(
                pairedDevices: pairedDevices,
                directDeviceIdentity: nil,
                inventory: inventory
            ),
            15
        )
    }

    func testCurrentDeviceBatteryLevelFallsBackToDirectDeviceInventory() {
        let inventory = [
            ConnectedBatteryDeviceInfo(id: "device-1", name: "MX Master 3", batteryLevel: 18)
        ]

        XCTAssertEqual(
            ConnectedBatteryDeviceInfo.currentDeviceBatteryLevel(
                pairedDevices: [],
                directDeviceIdentity: "device-1",
                inventory: inventory
            ),
            18
        )
    }
}
