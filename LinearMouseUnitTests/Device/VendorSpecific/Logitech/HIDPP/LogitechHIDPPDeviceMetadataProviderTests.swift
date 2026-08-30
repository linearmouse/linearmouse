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
}
