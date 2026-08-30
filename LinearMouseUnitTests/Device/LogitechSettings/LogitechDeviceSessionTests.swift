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
        session.runDPIOperation { _ in
            operationRan = true
        } onCancelled: {}

        session.cancelDPIApply()
        queueGate.signal()
        session.performSynchronously {}

        XCTAssertFalse(operationRan)
    }

    func testCancellingQueuedDPIOperationCompletesCancellationHandler() {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        let cancelled = expectation(description: "cancelled")

        session.runDPIOperation { _ in
            XCTFail("cancelled operation must not start")
        } onCancelled: {
            cancelled.fulfill()
        }

        session.cancelDPIApply()
        queueGate.signal()
        wait(for: [cancelled], timeout: 1)
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

    func testUnavailableChannelThenSameIdentityInvalidatesHardwareSessionTwice() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let initialDiscovery = discovery(serialNumber: "AAAAAAAA", productID: 0xB034)
        _ = session.updateDiscovery(initialDiscovery)
        var initialToken: CancellationToken?
        _ = session.adjustableDPI { _, currentToken in
            initialToken = currentToken
            return nil
        }

        let unavailable = session.updateDiscovery(.init(identities: [], route: nil))

        XCTAssertTrue(unavailable.hardwareTargetChanged)
        XCTAssertTrue(try XCTUnwrap(initialToken).isCancelled)

        let recovered = session.updateDiscovery(initialDiscovery)

        XCTAssertTrue(recovered.hardwareTargetChanged)
    }

    func testInitialWheelStateIsBoundToHardwareTarget() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.recordInitialHiResWheelState(enabled: false, for: access)

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB037))

        XCTAssertNil(session.initialHiResWheelEnabled(
            requiresReceiverRoute: true,
            receiverSlot: access.feature.receiverSlot
        ))
    }

    func testSupersededWheelAccessCannotMutateSessionState() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)

        session.cancelHiResWheelApply()
        session.recordInitialHiResWheelState(enabled: false, for: access)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)

        XCTAssertNil(session.initialHiResWheelEnabled(
            requiresReceiverRoute: true,
            receiverSlot: access.feature.receiverSlot
        ))
        XCTAssertNil(session.hiResWheelEnabled)
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
    }

    func testInitialWheelStateIsBoundToLegacyReceiverSlot() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.recordInitialHiResWheelState(enabled: false, for: access)

        XCTAssertFalse(try XCTUnwrap(session.initialHiResWheelEnabled(
            requiresReceiverRoute: false,
            receiverSlot: 2
        )))
        XCTAssertNil(session.initialHiResWheelEnabled(
            requiresReceiverRoute: false,
            receiverSlot: 3
        ))
    }

    func testWheelRestoreCommitsActualModeBeforeDiscardingInitialState() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.recordInitialHiResWheelState(enabled: false, for: access)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)

        // An acknowledged write changes the runtime cache but must not consume
        // the original target before the coordinator's readback phase.
        XCTAssertFalse(try XCTUnwrap(session.initialHiResWheelEnabled(
            requiresReceiverRoute: false,
            receiverSlot: access.feature.receiverSlot
        )))

        session.completeHiResWheelRestore(enabled: false, multiplier: nil, for: access)

        XCTAssertEqual(session.hiResWheelEnabled, false)
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
        XCTAssertNil(session.initialHiResWheelEnabled(
            requiresReceiverRoute: false,
            receiverSlot: access.feature.receiverSlot
        ))
    }

    func testWheelRestoreKeepsNormalizerForOriginalHighResolutionMode() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.recordInitialHiResWheelState(enabled: true, for: access)
        session.updateHiResWheelState(enabled: false, multiplier: nil, for: access)

        session.completeHiResWheelRestore(enabled: true, multiplier: 8, for: access)

        XCTAssertEqual(session.hiResWheelEnabled, true)
        XCTAssertEqual(session.hiResWheelNormalizationMultiplier, 8)
    }

    func testNewWheelDesiredCancelsQueuedRestore() {
        let session = LogitechDeviceSession(deviceID: 1)
        let restoreToken = session.runHiResWheelOperation(waitUntilFinished: false) { _ in }

        session.startHiResWheelApply { _, _ in false }

        XCTAssertTrue(restoreToken.isCancelled)
    }

    func testNewWheelDesiredCancelsRetryingStopManagingRestore() {
        let session = LogitechDeviceSession(deviceID: 1)
        let restoreToken = session.startHiResWheelRestore { _, _ in false }

        session.startHiResWheelApply { _, _ in false }

        XCTAssertTrue(restoreToken.isCancelled)
    }

    func testSupersededRestoreCannotInvalidateNewWheelAccess() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let restoreToken = session.runHiResWheelOperation(waitUntilFinished: false) { _ in }
        session.startHiResWheelApply { _, _ in false }
        _ = try hiResWheelAccess(for: session, receiverSlot: 2)

        session.invalidateHiResWheel(for: restoreToken)

        XCTAssertNotNil(session.hiResWheel { _, _ in
            XCTFail("superseded restore must not clear the newer wheel access")
            return nil
        })
    }

    private func hiResWheelAccess(
        for session: LogitechDeviceSession,
        receiverSlot: UInt8? = nil
    ) throws -> LogitechDeviceSession.FeatureAccess<HiResWheel> {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: receiverSlot))
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
