// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechDeviceSessionTests: XCTestCase {
    func testRenewingTransportCancelsPreviousToken() {
        let session = LogitechDeviceSession(deviceID: 1)
        let token = session.withState { $0.dpiCancellationSource.token }

        session.renewDPITransport()

        XCTAssertTrue(token.isCancelled)
        XCTAssertTrue(session.withState { $0.dpiCancellationSource.token.shouldContinue })
    }

    func testMetadataEnrichmentKeepsCurrentHardwareSession() {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        let token = session.withState { $0.dpiCancellationSource.token }

        let update = session.updateDiscovery(discovery(serialNumber: "513BBE34", productID: 0xB034))

        XCTAssertFalse(update.hardwareTargetChanged)
        XCTAssertTrue(token.shouldContinue)
    }

    func testReplacingDeviceInSameSlotCancelsHardwareSession() {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let token = session.withState { $0.dpiCancellationSource.token }

        let update = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB037))

        XCTAssertTrue(update.hardwareTargetChanged)
        XCTAssertTrue(token.isCancelled)
    }

    private func discovery(
        serialNumber: String?,
        productID: Int
    ) -> LogitechReceiverDiscovery {
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 123,
            slot: 2,
            kind: .mouse,
            name: "MX Mouse",
            serialNumber: serialNumber,
            productID: productID,
            batteryLevel: nil
        )
        return .init(
            identities: [identity],
            route: .init(slot: identity.slot, identity: identity)
        )
    }
}
