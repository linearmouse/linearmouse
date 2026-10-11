// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class DeviceMatcherTests: XCTestCase {
    /// What macOS reports for a Logi Bolt receiver with a paired mouse.
    private let receiver = DeviceMatcher(
        vendorID: 0x046D,
        productID: 0xC548,
        productName: "USB Receiver",
        serialNumber: nil,
        category: [.mouse]
    )

    /// What macOS reports for the same mouse connected over Bluetooth.
    private let bluetoothMouse = DeviceMatcher(
        vendorID: 0x046D,
        productID: 0xB042,
        productName: "MX Master 4",
        serialNumber: "11D5D259",
        category: [.mouse]
    )

    private func identity(
        productID: Int? = 0xB042,
        serialNumber: String? = "11D5D259",
        name: String = "MX Master 4"
    ) -> ReceiverLogicalDeviceIdentity {
        ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x0110_0000,
            slot: 1,
            kind: .mouse,
            name: name,
            serialNumber: serialNumber,
            productID: productID,
            batteryLevel: nil
        )
    }

    func testResolvedReceiverRouteIsMatchedAsThePairedDevice() {
        let candidates = DeviceMatchCandidates(physical: receiver, logicalIdentity: identity())

        XCTAssertEqual(candidates.primary, bluetoothMouse)
        XCTAssertEqual(candidates.fallback, receiver)
        XCTAssertEqual(candidates.all, [bluetoothMouse, receiver])
    }

    func testUnresolvedRouteKeepsThePhysicalIdentity() {
        let candidates = DeviceMatchCandidates(physical: receiver, logicalIdentity: nil)

        XCTAssertEqual(candidates.primary, receiver)
        XCTAssertNil(candidates.fallback)
        XCTAssertEqual(candidates.all, [receiver])
    }

    func testIdentityWithoutProductIDOrSerialKeepsThePhysicalIdentity() {
        let candidates = DeviceMatchCandidates(
            physical: receiver,
            logicalIdentity: identity(productID: nil, serialNumber: nil, name: "USB Receiver")
        )

        XCTAssertEqual(candidates.primary, receiver)
        XCTAssertNil(candidates.fallback)
    }

    func testIdentityWithSerialOnlyStillMatchesTheBluetoothScheme() {
        let candidates = DeviceMatchCandidates(
            physical: receiver,
            logicalIdentity: identity(productID: nil)
        )
        let bluetoothScheme = Scheme(if: [.init(device: bluetoothMouse)])

        // The receiver-side identity has no product ID, so a scheme written
        // against the Bluetooth identity cannot be proven to match it.
        XCTAssertFalse(bluetoothScheme.isActive(in: .init(
            deviceMatcher: candidates.primary,
            deviceFallback: candidates.fallback
        )))

        // A scheme written against the receiver-side identity matches both.
        let receiverSideScheme = Scheme(if: [.init(device: candidates.primary)])
        XCTAssertTrue(receiverSideScheme.isActive(in: .init(deviceMatcher: bluetoothMouse)))
    }

    func testSchemeWrittenOverBluetoothAppliesThroughTheReceiver() {
        let candidates = DeviceMatchCandidates(physical: receiver, logicalIdentity: identity())
        let scheme = Scheme(if: [.init(device: bluetoothMouse)])

        XCTAssertTrue(scheme.isActive(in: .init(
            deviceMatcher: candidates.primary,
            deviceFallback: candidates.fallback
        )))
    }

    func testSchemeWrittenAgainstTheReceiverStillApplies() {
        let candidates = DeviceMatchCandidates(physical: receiver, logicalIdentity: identity())
        let scheme = Scheme(if: [.init(device: receiver)])

        XCTAssertTrue(scheme.isActive(in: .init(
            deviceMatcher: candidates.primary,
            deviceFallback: candidates.fallback
        )))
    }

    func testSchemeWrittenThroughTheReceiverAppliesOverBluetooth() {
        let candidates = DeviceMatchCandidates(physical: receiver, logicalIdentity: identity())
        let context = Scheme.MatchContext(
            deviceMatcher: candidates.primary,
            deviceFallback: candidates.fallback
        )
        let scheme = Scheme(if: [.init(matchContext: context)])

        XCTAssertEqual(scheme.if?.first?.device, bluetoothMouse)
        XCTAssertTrue(scheme.isActive(in: .init(deviceMatcher: bluetoothMouse)))
    }

    func testAnotherMouseBehindTheSameReceiverDoesNotMatch() {
        let candidates = DeviceMatchCandidates(
            physical: receiver,
            logicalIdentity: identity(productID: 0xB034, serialNumber: "0A0B0C0D", name: "MX Master 3S")
        )
        let scheme = Scheme(if: [.init(device: bluetoothMouse)])

        XCTAssertFalse(scheme.isActive(in: .init(
            deviceMatcher: candidates.primary,
            deviceFallback: candidates.fallback
        )))
    }

    func testMatchedSchemeMergesBothIdentities() {
        let candidates = DeviceMatchCandidates(physical: receiver, logicalIdentity: identity())

        var bluetoothScheme = Scheme(if: [.init(device: bluetoothMouse)])
        bluetoothScheme.pointer.disableAcceleration = true
        var receiverScheme = Scheme(if: [.init(device: receiver)])
        receiverScheme.scrolling.reverse.vertical = true

        let configuration = Configuration(schemes: [bluetoothScheme, receiverScheme])
        let merged = configuration.matchScheme(in: .init(
            deviceMatcher: candidates.primary,
            deviceFallback: candidates.fallback
        ))

        XCTAssertEqual(merged.pointer.disableAcceleration, true)
        XCTAssertEqual(merged.scrolling.reverse.vertical, true)
    }
}
