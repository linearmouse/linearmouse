// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import PointerKit
import XCTest

final class LogitechReceiverRouteResolverTests: XCTestCase {
    func testOnlySupportedUSBReceiversRequireDiscovery() {
        XCTAssertTrue(LogitechReceiverRouteResolver.requiresDiscovery(for: receiver(productID: 0xC548)))
        XCTAssertTrue(LogitechReceiverRouteResolver.requiresDiscovery(for: receiver(productID: 0xC52B)))
        XCTAssertTrue(LogitechReceiverRouteResolver.requiresDiscovery(for: receiver(productID: 0xC539)))

        XCTAssertFalse(LogitechReceiverRouteResolver.requiresDiscovery(for: directBluetoothDevice()))
        XCTAssertFalse(LogitechReceiverRouteResolver.requiresDiscovery(for: directUSBDevice()))
        XCTAssertFalse(LogitechReceiverRouteResolver.requiresDiscovery(for: MockVendorSpecificDeviceContext(
            vendorID: 0x3554,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb
        )))
        XCTAssertFalse(LogitechReceiverRouteResolver.requiresDiscovery(for: receiver(
            productID: 0xC548,
            transport: PointerDeviceTransportName.bluetoothLowEnergy
        )))
    }

    func testReceiverRouteIsUnavailableBeforeDiscovery() {
        XCTAssertNil(LogitechReceiverRouteResolver.resolve(for: receiver(productID: 0xC548), identities: []))
    }

    func testSingleDiscoveredPointingDeviceProvidesRoute() throws {
        let identity = receiverIdentity(slot: 2, name: "MX Master 3S")

        let route = try XCTUnwrap(LogitechReceiverRouteResolver.resolve(
            for: receiver(productID: 0xC548),
            identities: [identity]
        ))

        XCTAssertEqual(route.slot, 2)
        XCTAssertEqual(route.identity, identity)
    }

    func testAmbiguousDiscoveryDoesNotGuessReceiverSlot() {
        XCTAssertNil(LogitechReceiverRouteResolver.resolve(
            for: receiver(productID: 0xC548),
            identities: [
                receiverIdentity(slot: 1, name: "MX Anywhere 3S"),
                receiverIdentity(slot: 2, name: "MX Master 3S")
            ]
        ))
    }

    func testRouteEqualityIgnoresBatteryOnlyUpdates() {
        let first = LogitechReceiverRoute(
            slot: 2,
            identity: receiverIdentity(slot: 2, name: "MX Master 3S", batteryLevel: 40)
        )
        let updated = LogitechReceiverRoute(
            slot: 2,
            identity: receiverIdentity(slot: 2, name: "MX Master 3S", batteryLevel: 80)
        )

        XCTAssertEqual(first, updated)
    }

    private func receiver(
        productID: Int,
        transport: String = PointerDeviceTransportName.usb
    ) -> MockVendorSpecificDeviceContext {
        MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: productID,
            product: "USB Receiver",
            transport: transport,
            locationID: 123
        )
    }

    private func directBluetoothDevice() -> MockVendorSpecificDeviceContext {
        MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            product: "MX Master 3S",
            transport: PointerDeviceTransportName.bluetoothLowEnergy
        )
    }

    private func directUSBDevice() -> MockVendorSpecificDeviceContext {
        MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            product: "G Mouse",
            transport: PointerDeviceTransportName.usb
        )
    }

    private func receiverIdentity(
        slot: UInt8,
        name: String,
        serialNumber: String? = nil,
        productID: Int? = nil,
        batteryLevel: Int? = nil
    ) -> ReceiverLogicalDeviceIdentity {
        ReceiverLogicalDeviceIdentity(
            receiverLocationID: 123,
            slot: slot,
            kind: .mouse,
            name: name,
            serialNumber: serialNumber,
            productID: productID,
            batteryLevel: batteryLevel
        )
    }
}
