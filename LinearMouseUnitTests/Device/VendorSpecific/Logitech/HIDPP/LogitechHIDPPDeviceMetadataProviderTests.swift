// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import PointerKit
import XCTest

final class LogitechHIDPPDeviceMetadataProviderTests: XCTestCase {
    func testLegacyReceiverSlotProbeRejectsAmbiguousIdentity() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB034,
            product: "MX Master 3S",
            serialNumber: "ABC123",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        let candidate = provider.receiverSlotCandidate(for: device, slots: [
            slot(slot: 1, name: "MX Master 3S", serialNumber: "ABC123", productID: 0xB034),
            slot(slot: 2, name: "MX Master 3S", serialNumber: "ABC123", productID: 0xB034)
        ])

        XCTAssertNil(candidate)
    }

    func testLegacyReceiverSlotProbeKeepsUniqueCompatibilityKindFallback() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Unknown Mouse",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(for: device, slots: [
            slot(slot: 1, kind: 0x02),
            slot(slot: 2, kind: 0x01)
        ]))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testKnownPartialInventoryRejectsSingletonFallback() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = mouseDevice()

        let candidate = provider.receiverSlotCandidate(
            for: device,
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x02)],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        )

        XCTAssertNil(candidate)
    }

    func testKnownCompleteInventoryAllowsSingleActiveCandidate() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = mouseDevice()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: device,
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x02)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testKnownEmptyInventoryHasNoCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [:],
            expectedConnectedDeviceCount: 0,
            inventoryAvailable: true
        ))
    }

    func testKnownPartialInventoryAllowsExactActiveSerialMatch() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Mouse",
            serialNumber: "ABC123",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: device,
            slots: [slot(slot: 1, name: "Mouse", serialNumber: "ABC123")],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x02)],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testUnknownCountKeepsLegacyCompatibilityFallback() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [:],
            expectedConnectedDeviceCount: nil,
            inventoryAvailable: false
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testMouseContextRejectsSingleKnownKeyboardCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x01)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownKeyboardSnapshotRejectsStaleMouseCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownMouseSnapshotRejectsStaleKeyboardCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.keyboard.rawValue, name: "Keyboard")],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownKeyboardSnapshotDoesNotBlockMouseRouteWhenCandidateIsStale() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [
                slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse"),
                slot(slot: 2, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Stale Mouse")
            ],
            connectionSnapshots: [
                1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
                2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)
            ],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testKnownCountKindResolutionAcceptsZeroMarkerAndRejectsUnsupportedKind() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let slots = [slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse")]

        let zeroMarker = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: slots,
            connectionSnapshots: [1: .init(isConnected: true, kind: 0)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
        XCTAssertEqual(zeroMarker.slot, 1)

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: slots,
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x06)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownCountKindResolutionAcceptsNilSnapshotWithKnownCandidate() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: nil)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testCompleteMouseAndKeyboardInventoryRoutesOnlyMouseCandidate() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [
                slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse"),
                slot(slot: 2, kind: ReceiverLogicalDeviceKind.keyboard.rawValue, name: "Keyboard")
            ],
            connectionSnapshots: [
                1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
                2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)
            ],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testMouseContextRejectsExactSerialOnKeyboardSnapshot() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Mouse",
            serialNumber: "ABC123",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        XCTAssertNil(provider.receiverSlotCandidate(
            for: device,
            slots: [slot(
                slot: 1,
                kind: ReceiverLogicalDeviceKind.keyboard.rawValue,
                serialNumber: "ABC123"
            )],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testPendingUnavailableChannelRequestsReopen() {
        XCTAssertEqual(
            ReceiverPendingDiscoveryDisposition.resolve(
                inventoryAvailable: false,
                channelReachable: false
            ),
            .reopenChannel
        )
        XCTAssertEqual(
            ReceiverPendingDiscoveryDisposition.resolve(
                inventoryAvailable: false,
                channelReachable: true
            ),
            .retryCurrentChannel
        )
    }

    func testReadyCountChangeEntersPendingOnlyWhenKnownCountChanges() {
        XCTAssertEqual(ReceiverReadyCountDisposition.resolve(previousCount: 2, currentCount: 2), .stayReady)
        XCTAssertEqual(ReceiverReadyCountDisposition.resolve(previousCount: 2, currentCount: 1), .enterPending)
        XCTAssertEqual(ReceiverReadyCountDisposition.resolve(previousCount: 2, currentCount: nil), .stayReady)
    }

    func testBoltOnDemandDiscoveryRejectsPartialSingletonAndAllowsCompleteInventory() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: 1,
            kind: .mouse,
            name: "Mouse",
            serialNumber: nil,
            productID: nil,
            batteryLevel: nil
        )
        let partial = LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        )

        XCTAssertNil(provider.receiverSlot(for: mouseDevice(), discovery: partial))

        let complete = LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        )

        XCTAssertEqual(try XCTUnwrap(provider.receiverSlot(for: mouseDevice(), discovery: complete)), 1)
    }

    func testCancelledCommittedCallbackTransactionDrainsItsResponse() {
        var response: Data?
        var waitCount = 0

        let result: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                waitCount += 1
                response = Data([0x11, 0xFF, 0x22, 0x18])
            },
            response: { response }
        )

        XCTAssertNil(result)
        XCTAssertEqual(waitCount, 1)
    }

    func testCancelledCommittedGetReportTransactionDrainsItsResponse() {
        var getReportResponse: Data?
        var pollCount = 0

        let result: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                pollCount += 1
                getReportResponse = Data([0x11, 0xFF, 0x22, 0x18])
            },
            response: { getReportResponse }
        )

        XCTAssertNil(result)
        XCTAssertEqual(pollCount, 1)
    }

    func testCommittedGetReportTransactionsUseIndependentTimedYields() {
        var firstResponse: Data?
        var secondResponse: Data?
        var firstPollCount = 0
        var secondPollCount = 0

        let firstResult: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                firstPollCount += 1
                firstResponse = Data([0x01])
            },
            response: { firstResponse }
        )
        let secondResult: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                secondPollCount += 1
                secondResponse = Data([0x02])
            },
            response: { secondResponse }
        )

        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)
        XCTAssertEqual(firstPollCount, 1)
        XCTAssertEqual(secondPollCount, 1)
    }

    private func slot(
        slot: UInt8,
        kind: UInt8 = 0x02,
        name: String? = nil,
        serialNumber: String? = nil,
        productID: Int? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotMatchCandidate {
        .init(
            slot: slot,
            kind: kind,
            name: name,
            serialNumber: serialNumber,
            productID: productID,
            batteryLevel: nil,
            hasLiveMetadata: name != nil || serialNumber != nil || productID != nil
        )
    }

    private func mouseDevice() -> MockVendorSpecificDeviceContext {
        MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Mouse",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )
    }
}
