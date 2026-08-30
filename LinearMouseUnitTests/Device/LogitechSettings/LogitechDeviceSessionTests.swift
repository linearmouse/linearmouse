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

    func testInitialDPIStateIsBoundToHardwareTarget() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try adjustableDPIAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: access))

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB037))

        XCTAssertNil(session.initialSensorDPI(for: access))
        XCTAssertFalse(session.hasInitialSensorDPIState)
    }

    func testSupersededDPIAccessCannotRecordOrConsumeBaseline() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try adjustableDPIAccess(for: session, receiverSlot: 2)

        session.cancelDPIApply()

        XCTAssertFalse(session.recordInitialSensorDPI(800, for: access))
        XCTAssertNil(session.initialSensorDPI(for: access))
        guard case .rejected = session.completeSensorDPIRestore(dpi: 800, for: access) else {
            XCTFail("A superseded access must not consume a DPI baseline")
            return
        }
    }

    func testInitialDPIStateIsBoundToLegacyReceiverSlot() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try adjustableDPIAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: access))

        session.cancelDPIApply()
        let otherAccess = try adjustableDPIAccess(for: session, receiverSlot: 3)

        XCTAssertNil(session.initialSensorDPI(for: otherAccess))
    }

    func testDPIBaselinePromotionAfterSerialEnrichment() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        let access = try adjustableDPIAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: access))

        let enriched = discovery(serialNumber: "513BBE34", productID: 0xB034)
        _ = session.updateDiscovery(enriched)
        let target = try receiverTarget(for: enriched)
        let lease = try XCTUnwrap(session.dpiTargetLease(receiverSlot: 2) { _, _ in target })
        let promotion = try XCTUnwrap(session.dpiBaselinePromotion(for: lease))
        let store = LogitechHardwareBaselineStore()
        let claim = store.captureDPIBaseline(promotion.dpi, for: target)

        XCTAssertEqual(promotion.dpi, 800)
        XCTAssertTrue(session.attachDPIBaseline(claim, to: promotion))
        XCTAssertTrue(session.hasStoredSensorDPIBaseline)

        _ = session.updateDiscovery(.init(identities: [], route: nil))
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        XCTAssertTrue(session.hasInitialSensorDPIState)
        XCTAssertNil(session.adjustableDPI { _, _ in
            XCTFail("An ambiguous stable target must remain quarantined")
            return nil
        })
    }

    func testDPIBaselineClearsForDifferentSerialAfterQuarantine() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let discoveryA = discovery(serialNumber: "AAAAAAAA", productID: 0xB034)
        _ = session.updateDiscovery(discoveryA)
        let targetA = try receiverTarget(for: discoveryA)
        let accessA = try adjustableDPIAccess(for: session, receiverSlot: 2, stableTargetKey: targetA)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: accessA))

        _ = session.updateDiscovery(.init(identities: [], route: nil))
        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB034))

        XCTAssertFalse(session.hasInitialSensorDPIState)
    }

    func testUnkeyedDPIBaselineClearsWhenReceiverRouteIsLost() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        let access = try adjustableDPIAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: access))

        _ = session.updateDiscovery(.init(identities: [], route: nil))

        XCTAssertFalse(session.hasInitialSensorDPIState)
    }

    func testSameStableDPIBaselineRebindsAcrossReceiverSlots() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let discoveryA = discovery(serialNumber: "AAAAAAAA", productID: 0xB034, slot: 2)
        _ = session.updateDiscovery(discoveryA)
        let targetA = try receiverTarget(for: discoveryA)
        let accessA = try adjustableDPIAccess(for: session, receiverSlot: 2, stableTargetKey: targetA)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: accessA))

        _ = session.updateDiscovery(.init(identities: [], route: nil))
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034, slot: 3))
        let reboundAccess = try adjustableDPIAccess(
            for: session,
            receiverSlot: 3,
            stableTargetKey: targetA
        )

        XCTAssertEqual(session.initialSensorDPI(for: reboundAccess), 800)
    }

    func testImplicitDPILeaseRetainsLegacyReceiverSlotWithoutPromotingReceiver() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try adjustableDPIAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: access))
        let receiverTarget = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "USB",
            locationID: 123,
            vendorID: 0x046D,
            productID: 0xC548,
            serialNumber: "RECEIVER",
            name: "USB Receiver"
        ))

        let lease = try XCTUnwrap(session.dpiTargetLease(receiverSlot: nil) { _, slot in
            XCTAssertEqual(slot, 2)
            return slot == nil ? receiverTarget : nil
        })

        XCTAssertEqual(lease.receiverSlot, 2)
        XCTAssertNil(lease.stableTargetKey)
        XCTAssertNil(session.dpiBaselinePromotion(for: lease))
    }

    func testReadbackConfirmedDPIRestoreReturnsExactConsumableHandle() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 123,
            vendorID: 0x046D,
            productID: 0xB034,
            serialNumber: "ABC123",
            name: "Mouse"
        ))
        let claim = store.captureDPIBaseline(800, for: target)
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try adjustableDPIAccess(for: session, stableTargetKey: target)
        let lease = try XCTUnwrap(session.dpiTargetLease(receiverSlot: nil) { _, _ in target })
        XCTAssertTrue(session.seedInitialSensorDPI(claim, for: lease))

        let commit = session.completeSensorDPIRestore(dpi: 800, for: access)
        guard case let .committed(handle?) = commit else {
            XCTFail("Expected a confirmed restore commit")
            return
        }
        XCTAssertTrue(store.consumeDPIBaseline(handle))
        XCTAssertNil(store.dpiBaseline(for: target))
    }

    func testFailedDPIRestoreRetainsBaselineForLaterAttempt() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 123,
            vendorID: 0x046D,
            productID: 0xB034,
            serialNumber: "ABC123",
            name: "Mouse"
        ))
        let claim = store.captureDPIBaseline(800, for: target)
        let session = LogitechDeviceSession(deviceID: 1)
        let lease = try XCTUnwrap(session.dpiTargetLease(receiverSlot: nil) { _, _ in target })
        XCTAssertTrue(session.seedInitialSensorDPI(claim, for: lease))

        // No read-back commit is made after the simulated failed write.
        XCTAssertEqual(store.dpiBaseline(for: target)?.baseline, .init(value: 800))
        XCTAssertTrue(session.hasInitialSensorDPIState)
    }

    func testInitialWheelStateIsBoundToHardwareTarget() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.recordInitialHiResWheelState(enabled: false, for: access)

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB037))

        XCTAssertNil(session.initialHiResWheelEnabled(for: access))
    }

    func testSupersededWheelAccessCannotMutateSessionState() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)

        session.cancelHiResWheelApply()
        session.recordInitialHiResWheelState(enabled: false, for: access)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)

        XCTAssertNil(session.initialHiResWheelEnabled(for: access))
        XCTAssertNil(session.hiResWheelEnabled)
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
    }

    func testInitialWheelStateIsBoundToLegacyReceiverSlot() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.recordInitialHiResWheelState(enabled: false, for: access)

        XCTAssertFalse(try XCTUnwrap(session.initialHiResWheelEnabled(for: access)))
        session.cancelHiResWheelApply()
        let otherAccess = try hiResWheelAccess(for: session, receiverSlot: 3)
        XCTAssertNil(session.initialHiResWheelEnabled(for: otherAccess))
    }

    func testWheelRestoreCommitsActualModeBeforeDiscardingInitialState() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.recordInitialHiResWheelState(enabled: false, for: access)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)

        // An acknowledged write changes the runtime cache but must not consume
        // the original target before the coordinator's readback phase.
        XCTAssertFalse(try XCTUnwrap(session.initialHiResWheelEnabled(for: access)))

        session.completeHiResWheelRestore(enabled: false, multiplier: nil, for: access)

        XCTAssertEqual(session.hiResWheelEnabled, false)
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
        XCTAssertNil(session.initialHiResWheelEnabled(for: access))
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

    func testOldSessionCommitCannotConsumeReplacementBaselineOwnership() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "USB",
            locationID: 123,
            vendorID: 0x046D,
            productID: 0xB034,
            serialNumber: "ABC123",
            name: "Mouse"
        ))
        let oldClaim = store.captureHiResBaseline(enabled: false, for: target)
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session, stableTargetKey: target)
        let lease = try XCTUnwrap(session.hiResWheelTargetLease(
            receiverSlot: nil
        ) { _, _ in target })
        XCTAssertTrue(session.seedInitialHiResWheelState(oldClaim, for: lease))

        XCTAssertTrue(store.consumeHiResBaseline(oldClaim.handle))
        let newClaim = store.captureHiResBaseline(enabled: true, for: target)

        let commit = session.completeHiResWheelRestore(enabled: false, multiplier: nil, for: access)
        guard case let .committed(handle?) = commit else {
            XCTFail("current session must commit its restore")
            return
        }

        XCTAssertFalse(store.consumeHiResBaseline(handle))
        XCTAssertEqual(store.hiResBaseline(for: target)?.baseline, newClaim.baseline)
    }

    func testExtendedSerialEnrichmentPromotesSavedInitialMode() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        let originalAccess = try hiResWheelAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: originalAccess))

        let enriched = discovery(serialNumber: "513BBE34", productID: 0xB034)
        _ = session.updateDiscovery(enriched)
        let target = try receiverTarget(for: enriched)
        let lease = try XCTUnwrap(session.hiResWheelTargetLease(
            receiverSlot: 2
        ) { _, _ in target })
        let promotion = try XCTUnwrap(session.hiResBaselinePromotion(for: lease))
        let store = LogitechHardwareBaselineStore()
        let claim = store.captureHiResBaseline(enabled: promotion.enabled, for: target)

        XCTAssertFalse(promotion.enabled)
        XCTAssertTrue(session.attachHiResBaseline(claim, to: promotion))
        XCTAssertTrue(session.hasStoredHiResWheelBaseline)
        let reboundAccess = try hiResWheelAccess(
            for: session,
            receiverSlot: 2,
            stableTargetKey: target
        )
        XCTAssertEqual(reboundAccess.lease.stableTargetKey, target)

        _ = session.updateDiscovery(.init(identities: [], route: nil))
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        XCTAssertTrue(session.hasStoredHiResWheelBaseline)
        XCTAssertNil(session.hiResWheel { _, _ in nil })
    }

    func testReadInFlightDuringEnrichmentPromotesUsingCurrentLease() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        let accessAtReadStart = try hiResWheelAccess(for: session, receiverSlot: 2)

        let enriched = discovery(serialNumber: "513BBE34", productID: 0xB034)
        _ = session.updateDiscovery(enriched)
        let target = try receiverTarget(for: enriched)
        let currentLease = try XCTUnwrap(session.hiResWheelTargetLease(
            receiverSlot: 2
        ) { _, _ in target })
        XCTAssertNil(session.hiResBaselinePromotion(for: currentLease))

        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: accessAtReadStart))

        let promotion = try XCTUnwrap(session.hiResBaselinePromotion(for: currentLease))
        XCTAssertFalse(promotion.enabled)
        XCTAssertEqual(promotion.target, target)
    }

    func testSeedRejectsLeaseAfterRouteChangesToDifferentSerial() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let discoveryA = discovery(serialNumber: "AAAAAAAA", productID: 0xB034)
        _ = session.updateDiscovery(discoveryA)
        let targetA = try receiverTarget(for: discoveryA)
        let leaseA = try XCTUnwrap(session.hiResWheelTargetLease(
            receiverSlot: 2
        ) { _, _ in targetA })
        let store = LogitechHardwareBaselineStore()
        let claimA = store.captureHiResBaseline(enabled: false, for: targetA)

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB034))

        XCTAssertFalse(session.seedInitialHiResWheelState(claimA, for: leaseA))
        XCTAssertFalse(session.hasInitialHiResWheelState)
    }

    func testOldAccessCannotRecordForReplacementRoute() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let discoveryA = discovery(serialNumber: "AAAAAAAA", productID: 0xB034)
        _ = session.updateDiscovery(discoveryA)
        let accessA = try hiResWheelAccess(
            for: session,
            receiverSlot: 2,
            stableTargetKey: receiverTarget(for: discoveryA)
        )

        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))

        XCTAssertFalse(session.recordInitialHiResWheelState(enabled: false, for: accessA))
        XCTAssertFalse(session.hasInitialHiResWheelState)
    }

    func testStableBaselineQuarantinesAmbiguousRouteThenClearsDifferentSerial() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let discoveryA = discovery(serialNumber: "AAAAAAAA", productID: 0xB034)
        _ = session.updateDiscovery(discoveryA)
        let targetA = try receiverTarget(for: discoveryA)
        let accessA = try hiResWheelAccess(for: session, receiverSlot: 2, stableTargetKey: targetA)
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: accessA))

        _ = session.updateDiscovery(.init(identities: [], route: nil))
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))

        XCTAssertTrue(session.hasInitialHiResWheelState)
        XCTAssertNil(session.hiResWheel { _, _ in
            XCTFail("ambiguous route must remain quarantined")
            return nil
        })

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB034))
        XCTAssertFalse(session.hasInitialHiResWheelState)
    }

    func testSameStableSerialRebindsAcrossReceiverSlots() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let discoveryA = discovery(serialNumber: "AAAAAAAA", productID: 0xB034, slot: 2)
        _ = session.updateDiscovery(discoveryA)
        let targetA = try receiverTarget(for: discoveryA)
        let accessA = try hiResWheelAccess(for: session, receiverSlot: 2, stableTargetKey: targetA)
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: accessA))

        _ = session.updateDiscovery(.init(identities: [], route: nil))
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034, slot: 3))
        let reboundAccess = try hiResWheelAccess(
            for: session,
            receiverSlot: 3,
            stableTargetKey: targetA
        )

        XCTAssertEqual(session.initialHiResWheelEnabled(for: reboundAccess), false)
    }

    func testUnkeyedReceiverBaselineIsClearedWhenRouteIsLost() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: access))

        _ = session.updateDiscovery(.init(identities: [], route: nil))

        XCTAssertFalse(session.hasInitialHiResWheelState)
    }

    func testImplicitLeaseDoesNotPromoteOnDemandReceiverAsDirectDevice() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: access))
        let receiverTarget = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "USB",
            locationID: 123,
            vendorID: 0x046D,
            productID: 0xC548,
            serialNumber: "LOGICAL-MOUSE",
            name: "Mouse"
        ))

        let lease = try XCTUnwrap(session.hiResWheelTargetLease(receiverSlot: nil) { _, slot in
            XCTAssertEqual(slot, 2)
            // This mirrors Device.logitechHardwareTargetKey: a routed slot is
            // unkeyed, while nil would incorrectly identify the receiver itself.
            return slot == nil ? receiverTarget : nil
        })

        XCTAssertEqual(lease.receiverSlot, 2)
        XCTAssertNil(lease.stableTargetKey)
        XCTAssertNil(session.hiResBaselinePromotion(for: lease))
        XCTAssertEqual(session.initialHiResWheelEnabled(for: access), false)
    }

    func testImplicitLeaseKeepsNilSlotForDirectDevice() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let target = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 123,
            vendorID: 0x046D,
            productID: 0xB034,
            serialNumber: "DIRECT-MOUSE",
            name: "Mouse"
        ))
        let access = try hiResWheelAccess(for: session, stableTargetKey: target)
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: access))

        let lease = try XCTUnwrap(session.hiResWheelTargetLease(receiverSlot: nil) { route, slot in
            XCTAssertNil(route)
            XCTAssertNil(slot)
            return target
        })

        XCTAssertNil(lease.receiverSlot)
        XCTAssertEqual(lease.stableTargetKey, target)
        let promotion = try XCTUnwrap(session.hiResBaselinePromotion(for: lease))
        let store = LogitechHardwareBaselineStore()
        let claim = store.captureHiResBaseline(enabled: promotion.enabled, for: target)
        XCTAssertTrue(session.attachHiResBaseline(claim, to: promotion))
        XCTAssertEqual(session.initialHiResWheelEnabled(for: access), false)
    }

    private func hiResWheelAccess(
        for session: LogitechDeviceSession,
        receiverSlot: UInt8? = nil,
        stableTargetKey: LogitechHardwareTargetKey? = nil
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
            .init(
                feature: HiResWheel(transport: transport, featureIndex: 1),
                stableTargetKey: stableTargetKey,
                receiverSlot: receiverSlot
            )
        })
    }

    private func adjustableDPIAccess(
        for session: LogitechDeviceSession,
        receiverSlot: UInt8? = nil,
        stableTargetKey: LogitechHardwareTargetKey? = nil
    ) throws -> LogitechDeviceSession.FeatureAccess<AdjustableDPI> {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: receiverSlot))
        return try XCTUnwrap(session.adjustableDPI { _, _ in
            .init(
                feature: AdjustableDPI(
                    transport: transport,
                    featureIndex: 1,
                    supportedDPI: [400, 800, 1200, 8000]
                ),
                stableTargetKey: stableTargetKey,
                receiverSlot: receiverSlot
            )
        })
    }

    private func receiverTarget(
        for discovery: LogitechReceiverDiscovery
    ) throws -> LogitechHardwareTargetKey {
        let identity = try XCTUnwrap(discovery.route?.identity)
        return try XCTUnwrap(LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: identity.receiverLocationID,
            identity: identity
        ))
    }

    private func discovery(
        serialNumber: String?,
        productID: Int,
        slot: UInt8 = 2
    ) -> LogitechReceiverDiscovery {
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 123,
            slot: slot,
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
