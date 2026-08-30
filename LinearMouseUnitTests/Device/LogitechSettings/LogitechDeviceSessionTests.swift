// MIT License
// Copyright (c) 2021-2026 LinearMouse

import HIDPP
@testable import LinearMouse
import PointerKit
import XCTest

final class LogitechDeviceSessionTests: XCTestCase {
    func testRenewingTransportCancelsPreviousToken() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        var token: CancellationToken?
        _ = session.adjustableDPI { _, currentToken in
            token = currentToken
            return nil
        }

        let initialToken = try XCTUnwrap(token)
        session.cancelDPIApply()

        XCTAssertTrue(initialToken.isCancelled)
        XCTAssertNil(session.adjustableDPI(expectedToken: initialToken) { _, _ in
            XCTFail("A superseded operation must not create a controller")
            return nil
        })
    }

    func testCancellingQueuedDPIOperationPreventsItFromStarting() {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        var operationRan = false
        session.runDPIOperation { _ in operationRan = true }

        session.cancelDPIApply()
        queueGate.signal()
        session.performSynchronously {}

        XCTAssertFalse(operationRan)
    }

    func testMetadataEnrichmentKeepsCurrentHardwareSession() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        var token: CancellationToken?
        _ = session.adjustableDPI { _, currentToken in
            token = currentToken
            return nil
        }

        let update = session.updateDiscovery(discovery(serialNumber: "513BBE34", productID: 0xB034))

        XCTAssertFalse(update.hardwareTargetChanged)
        XCTAssertTrue(try XCTUnwrap(token).shouldContinue)
    }

    func testReplacingDeviceInSameSlotCancelsHardwareSession() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        var token: CancellationToken?
        _ = session.adjustableDPI { _, currentToken in
            token = currentToken
            return nil
        }

        let update = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB037))

        XCTAssertTrue(update.hardwareTargetChanged)
        XCTAssertTrue(try XCTUnwrap(token).isCancelled)
    }

    func testInitialWheelStateIsBoundToHardwareTarget() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try hiResWheelAccess(for: session)
        session.recordInitialHiResWheelState(enabled: false, for: access)

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB037))

        XCTAssertNil(session.initialHiResWheelEnabled(requiresReceiverRoute: true))
    }

    func testSupersededWheelAccessCannotMutateSessionState() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try hiResWheelAccess(for: session)

        session.cancelHiResWheelApply()
        session.recordInitialHiResWheelState(enabled: false, for: access)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)

        XCTAssertNil(session.initialHiResWheelEnabled(requiresReceiverRoute: true))
        XCTAssertNil(session.hiResWheelEnabled)
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
    }

    private func hiResWheelAccess(
        for session: LogitechDeviceSession
    ) throws -> LogitechDeviceSession.FeatureAccess<HiResWheel> {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        return try XCTUnwrap(session.hiResWheel { _, _ in
            HiResWheel(transport: transport, featureIndex: 1)
        })
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
