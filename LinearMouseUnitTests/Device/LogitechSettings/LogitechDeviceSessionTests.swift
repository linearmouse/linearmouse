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

    func testTerminalHardwareRestoreRetainsCurrentFeatureAccesses() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = try adjustableDPIAccess(for: session)
        _ = try hiResWheelAccess(for: session)
        let completed = expectation(description: "terminal restore")

        session.runTerminalHardwareRestore { dpiToken, wheelToken, _ in
            let retainedDPI = session.adjustableDPI(expectedToken: dpiToken) { _, _ in
                XCTFail("Terminal restore should reuse the current DPI feature")
                return nil
            }
            let retainedWheel = session.hiResWheel(expectedToken: wheelToken) { _, _ in
                XCTFail("Terminal restore should reuse the current wheel feature")
                return nil
            }

            XCTAssertNotNil(retainedDPI)
            XCTAssertNotNil(retainedWheel)
            completed.fulfill()
        } onCancelled: {
            XCTFail("Current terminal restore should not be cancelled")
        }

        wait(for: [completed], timeout: 1)
    }

    func testPreparedTerminalSessionRunsRestoreThroughTheSameOwner() {
        let session = LogitechDeviceSession(deviceID: 1)
        session.freezeTerminalHardwareMutations()
        let completed = expectation(description: "prepared terminal restore")

        session.runTerminalHardwareRestore { _, _, ownsTerminalRestore in
            XCTAssertTrue(ownsTerminalRestore())
            completed.fulfill()
        } onCancelled: {
            XCTFail("The prepared terminal owner should be reused")
        }

        wait(for: [completed], timeout: 1)
    }

    func testCancellingOneQueuedTerminalFeatureDoesNotStarveTheOther() {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        let ran = expectation(description: "terminal restore ran")

        session.runTerminalHardwareRestore { dpiToken, wheelToken, _ in
            XCTAssertFalse(dpiToken.shouldContinue)
            XCTAssertTrue(wheelToken.shouldContinue)
            ran.fulfill()
        } onCancelled: {
            XCTFail("The terminal owner itself remains current")
        }

        session.cancelDPIApply()
        queueGate.signal()
        wait(for: [ran], timeout: 1)
    }

    func testRepeatedHardwareSuspensionReturnsTheSameOwner() throws {
        let session = LogitechDeviceSession(deviceID: 1)

        let first = try XCTUnwrap(session.suspendHardware())
        let duplicate = try XCTUnwrap(session.suspendHardware())
        let unrelated = try XCTUnwrap(LogitechDeviceSession(deviceID: 2).suspendHardware())

        XCTAssertIdentical(first, duplicate)
        XCTAssertFalse(session.resumeHardware(from: unrelated))
        XCTAssertTrue(session.resumeHardware(from: first))
        XCTAssertFalse(session.resumeHardware(from: duplicate))
    }

    func testTerminalHardwareRestoreRejectsNewSettingMutation() {
        let session = LogitechDeviceSession(deviceID: 1)
        let terminalStarted = expectation(description: "terminal restore started")
        let releaseTerminal = DispatchSemaphore(value: 0)

        session.runTerminalHardwareRestore { _, _, _ in
            terminalStarted.fulfill()
            releaseTerminal.wait()
        } onCancelled: {
            XCTFail("The first terminal request owns this session")
        }
        wait(for: [terminalStarted], timeout: 1)

        var manualOperationRan = false
        let manualCancelled = expectation(description: "manual mutation rejected")
        session.runDPIOperation { _ in
            manualOperationRan = true
        } onCancelled: {
            manualCancelled.fulfill()
        }
        wait(for: [manualCancelled], timeout: 1)

        var configuredApplyRan = false
        session.startDPIApply { _, _ in
            configuredApplyRan = true
            return true
        }

        releaseTerminal.signal()
        session.performSynchronously {}
        XCTAssertFalse(manualOperationRan)
        XCTAssertFalse(configuredApplyRan)
    }

    func testTerminalRequestRejectsOrdinaryOperationAcceptedBeforeItWasInstalled() {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        var ordinaryOperationRan = false
        let ordinaryCancelled = expectation(description: "queued ordinary mutation cancelled")

        session.runDPIOperation { _ in
            ordinaryOperationRan = true
        } onCancelled: {
            ordinaryCancelled.fulfill()
        }

        let terminalCompleted = expectation(description: "terminal restore ran")
        session.runTerminalHardwareRestore { _, _, _ in
            terminalCompleted.fulfill()
        } onCancelled: {
            XCTFail("terminal restore must retain ownership")
        }

        queueGate.signal()
        wait(for: [ordinaryCancelled, terminalCompleted], timeout: 1)
        XCTAssertFalse(ordinaryOperationRan)
    }

    func testTerminalCancelsQueuedOrdinaryHardwareRead() {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        let readCancelled = expectation(description: "ordinary read cancelled")
        let terminalRan = expectation(description: "terminal restore ran")

        session.runBoundedOrdinaryHardwareRead(
            deadline: Date().addingTimeInterval(1)
        ) {
            _ in XCTFail("queued ordinary read must not start")
        } onCancelled: {
            readCancelled.fulfill()
        }
        session.runTerminalHardwareRestore { _, _, _ in
            terminalRan.fulfill()
        } onCancelled: {
            XCTFail("terminal restore must retain ownership")
        }

        queueGate.signal()
        wait(for: [readCancelled, terminalRan], timeout: 1)
    }

    func testHardwareSuspensionCancelsQueuedOrdinaryHardwareRead() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        let readCancelled = expectation(description: "ordinary read cancelled")

        session.runBoundedOrdinaryHardwareRead(
            deadline: Date().addingTimeInterval(1)
        ) {
            _ in XCTFail("queued ordinary read must not start")
        } onCancelled: {
            readCancelled.fulfill()
        }
        let suspension = try XCTUnwrap(session.suspendHardware())

        queueGate.signal()
        wait(for: [readCancelled], timeout: 1)
        XCTAssertTrue(session.resumeHardware(from: suspension))
    }

    func testTerminalCancelsInFlightOrdinaryHardwareRead() {
        let session = LogitechDeviceSession(deviceID: 1)
        let readStarted = expectation(description: "ordinary read started")
        let inspectAdmission = DispatchSemaphore(value: 0)
        let readStopped = expectation(description: "ordinary read stopped")

        session.runBoundedOrdinaryHardwareRead(
            deadline: Date().addingTimeInterval(1)
        ) { shouldContinue in
            XCTAssertTrue(shouldContinue())
            readStarted.fulfill()
            inspectAdmission.wait()
            XCTAssertFalse(shouldContinue())
            readStopped.fulfill()
        } onCancelled: {
            XCTFail("read began before terminal admission")
        }
        wait(for: [readStarted], timeout: 1)

        session.freezeTerminalHardwareMutations()
        inspectAdmission.signal()
        wait(for: [readStopped], timeout: 1)
    }

    func testHardwareSuspensionCancelsInFlightOrdinaryHardwareRead() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let readStarted = expectation(description: "ordinary read started")
        let inspectAdmission = DispatchSemaphore(value: 0)
        let readStopped = expectation(description: "ordinary read stopped")

        session.runBoundedOrdinaryHardwareRead(
            deadline: Date().addingTimeInterval(1)
        ) { shouldContinue in
            XCTAssertTrue(shouldContinue())
            readStarted.fulfill()
            inspectAdmission.wait()
            XCTAssertFalse(shouldContinue())
            readStopped.fulfill()
        } onCancelled: {
            XCTFail("read began before suspension admission")
        }
        wait(for: [readStarted], timeout: 1)

        let suspension = try XCTUnwrap(session.suspendHardware())
        inspectAdmission.signal()
        wait(for: [readStopped], timeout: 1)
        XCTAssertTrue(session.resumeHardware(from: suspension))
    }

    func testOrdinaryHardwareReadHonorsOneAbsoluteDeadline() {
        let session = LogitechDeviceSession(deviceID: 1)
        let cancelled = expectation(description: "expired read cancelled")

        session.runBoundedOrdinaryHardwareRead(
            deadline: Date(timeIntervalSince1970: 0)
        ) {
            _ in XCTFail("expired read must not start")
        } onCancelled: {
            cancelled.fulfill()
        }

        wait(for: [cancelled], timeout: 1)
    }

    func testTerminalRestoreRetriesOnlyUnfinishedSettings() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        var dpiAttempts = 0
        var wheelAttempts = 0
        var waits = [TimeInterval]()

        let restored = LogitechTerminalHardwareRestoreRetry.perform(
            operations: [
                .init(
                    shouldContinue: { true },
                    attempt: { _ in
                        dpiAttempts += 1
                        return dpiAttempts == 1
                    }
                ),
                .init(
                    shouldContinue: { true },
                    attempt: { _ in
                        wheelAttempts += 1
                        return wheelAttempts == 2
                    }
                )
            ],
            deadline: currentTime.addingTimeInterval(1),
            now: { currentTime },
            wait: { delay in
                waits.append(delay)
                currentTime.addTimeInterval(delay)
            }
        )

        XCTAssertTrue(restored)
        XCTAssertEqual(dpiAttempts, 1)
        XCTAssertEqual(wheelAttempts, 2)
        XCTAssertEqual(waits, [0.05])
    }

    func testTerminalRestoreRetryStopsWhenOwnerIsCancelled() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        var shouldContinue = true
        var attempts = 0

        let restored = LogitechTerminalHardwareRestoreRetry.perform(
            operations: [
                .init(
                    shouldContinue: { shouldContinue },
                    attempt: { _ in
                        attempts += 1
                        return false
                    }
                )
            ],
            deadline: currentTime.addingTimeInterval(1),
            now: { currentTime },
            wait: { delay in
                currentTime.addTimeInterval(delay)
                shouldContinue = false
            }
        )

        XCTAssertFalse(restored)
        XCTAssertEqual(attempts, 1)
    }

    func testSlowDPIAttemptCannotStarveWheelRestore() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let deadline = currentTime.addingTimeInterval(4)
        var dpiAttempts = 0
        var wheelAttempts = 0

        let restored = LogitechTerminalHardwareRestoreRetry.perform(
            operations: [
                .init(
                    shouldContinue: { true },
                    attempt: { attempt in
                        dpiAttempts += 1
                        // Model a read/set/read path that consumes every second
                        // granted to this setting.
                        currentTime = attempt.deadline
                        return false
                    }
                ),
                .init(
                    shouldContinue: { true },
                    attempt: { _ in
                        wheelAttempts += 1
                        return true
                    }
                )
            ],
            deadline: deadline,
            now: { currentTime },
            wait: { currentTime.addTimeInterval($0) }
        )

        XCTAssertFalse(restored)
        XCTAssertGreaterThanOrEqual(dpiAttempts, 1)
        XCTAssertEqual(wheelAttempts, 1)
    }

    func testInFlightConfiguredWriteLosesAdmissionWhenTerminalRestoreBegins() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try adjustableDPIAccess(for: session)
        let operationStarted = expectation(description: "configured operation started")
        let inspectAdmission = DispatchSemaphore(value: 0)
        let admissionChecked = expectation(description: "write admission checked")

        session.perform {
            operationStarted.fulfill()
            inspectAdmission.wait()
            XCTAssertFalse(session.allowsConfiguredDPIWrite(for: access))
            admissionChecked.fulfill()
        }
        wait(for: [operationStarted], timeout: 1)

        let terminalRan = expectation(description: "terminal restore ran")
        session.runTerminalHardwareRestore { _, _, ownsTerminalRestore in
            XCTAssertTrue(ownsTerminalRestore())
            terminalRan.fulfill()
        } onCancelled: {
            XCTFail("terminal owner should remain current")
        }
        inspectAdmission.signal()

        wait(for: [admissionChecked, terminalRan], timeout: 1)
    }

    func testHardwareSuspensionSupersedesInFlightAccessAndPreservesRuntimeContext() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try adjustableDPIAccess(for: session)
        let wheelAccess = try hiResWheelAccess(for: session)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: access))
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: wheelAccess))
        session.updateSensorDPI(8000, for: access)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: wheelAccess)
        let oldApplyStarted = expectation(description: "old apply started")
        let releaseOldApply = DispatchSemaphore(value: 0)
        let admissionChecked = expectation(description: "old access rejected")

        session.perform {
            oldApplyStarted.fulfill()
            releaseOldApply.wait()
            XCTAssertFalse(session.allowsConfiguredDPIWrite(for: access))
            XCTAssertFalse(session.allowsConfiguredHiResWheelWrite(for: wheelAccess))
            admissionChecked.fulfill()
        }
        wait(for: [oldApplyStarted], timeout: 1)

        let suspension = try XCTUnwrap(session.suspendHardware())
        XCTAssertFalse(session.allowsConfiguredDPIWrite(for: access))
        XCTAssertFalse(session.allowsConfiguredHiResWheelWrite(for: wheelAccess))
        XCTAssertNil(session.sensorDPI)
        XCTAssertNil(session.hiResWheelEnabled)
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
        XCTAssertTrue(session.hasInitialSensorDPIState)
        XCTAssertTrue(session.hasInitialHiResWheelState)
        releaseOldApply.signal()
        wait(for: [admissionChecked], timeout: 1)

        XCTAssertTrue(session.resumeHardware(from: suspension))
        XCTAssertEqual(session.hiResWheelNormalizationMultiplier, 8)
        let resumedDPIAccess = try adjustableDPIAccess(for: session)
        let resumedWheelAccess = try hiResWheelAccess(for: session)
        XCTAssertEqual(session.initialSensorDPI(for: resumedDPIAccess), 800)
        XCTAssertFalse(try XCTUnwrap(session.initialHiResWheelEnabled(for: resumedWheelAccess)))
    }

    func testTerminalRestoreSupersedesSuspensionAndRejectsLateResume() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        let terminalRan = expectation(description: "terminal restore ran")
        let suspension = try XCTUnwrap(session.suspendHardware())

        session.runTerminalHardwareRestore { _, _, ownsTerminalRestore in
            XCTAssertTrue(ownsTerminalRestore())
            terminalRan.fulfill()
        } onCancelled: {
            XCTFail("terminal restore is the stronger concrete owner")
        }
        XCTAssertFalse(session.resumeHardware(from: suspension))
        XCTAssertNil(session.suspendHardware())
        queueGate.signal()

        wait(for: [terminalRan], timeout: 1)
    }

    func testTerminalRestoreAfterSuspensionUsesFreshTokensAndPreservedBaselines() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let dpiAccess = try adjustableDPIAccess(for: session)
        let wheelAccess = try hiResWheelAccess(for: session)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: dpiAccess))
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: wheelAccess))
        let suspension = try XCTUnwrap(session.suspendHardware())
        let terminalRan = expectation(description: "terminal restore ran")

        session.runTerminalHardwareRestore { dpiToken, wheelToken, ownsTerminalRestore in
            XCTAssertTrue(ownsTerminalRestore())
            guard let terminalDPIAccess = try? self.adjustableDPIAccess(
                for: session,
                expectedToken: dpiToken
            ), let terminalWheelAccess = try? self.hiResWheelAccess(
                for: session,
                expectedToken: wheelToken
            ) else {
                XCTFail("terminal owner must recreate both suspended features")
                terminalRan.fulfill()
                return
            }
            XCTAssertEqual(session.initialSensorDPI(for: terminalDPIAccess), 800)
            XCTAssertFalse(session.initialHiResWheelEnabled(for: terminalWheelAccess) ?? true)
            terminalRan.fulfill()
        } onCancelled: {
            XCTFail("terminal owner must supersede suspension")
        }

        wait(for: [terminalRan], timeout: 1)
        XCTAssertFalse(session.resumeHardware(from: suspension))
    }

    func testSuspensionPreservesStoreBackedAndUnkeyedInitialState() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let target = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 123,
            vendorID: 0x046D,
            productID: 0xB034,
            serialNumber: "ABC123",
            name: "Mouse"
        ))
        let dpiAccess = try adjustableDPIAccess(for: session, stableTargetKey: target)
        let wheelAccess = try hiResWheelAccess(for: session)
        XCTAssertTrue(session.recordInitialSensorDPI(800, for: dpiAccess))
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: wheelAccess))
        let lease = try XCTUnwrap(session.dpiTargetLease(receiverSlot: nil) { _, _ in target })
        let promotion = try XCTUnwrap(session.dpiBaselinePromotion(for: lease))
        let store = LogitechHardwareBaselineStore()
        let claim = store.captureDPIBaseline(promotion.dpi, for: target)
        XCTAssertTrue(session.attachDPIBaseline(claim, to: promotion))

        let suspension = try XCTUnwrap(session.suspendHardware())
        XCTAssertTrue(session.hasInitialSensorDPIState)
        XCTAssertTrue(session.hasInitialHiResWheelState)
        XCTAssertEqual(store.dpiBaseline(for: target)?.baseline, .init(value: 800))
        XCTAssertTrue(session.resumeHardware(from: suspension))
    }

    func testSuspensionRejectsOrdinaryMutationUntilExactResume() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let suspension = try XCTUnwrap(session.suspendHardware())
        let unrelated = try XCTUnwrap(LogitechDeviceSession(deviceID: 2).suspendHardware())
        let rejected = expectation(description: "suspended mutation rejected")
        XCTAssertFalse(session.allowsOrdinaryHardwareIO)

        session.runDPIOperation { _ in
            XCTFail("suspended session must reject ordinary mutation")
        } onCancelled: {
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 1)

        XCTAssertFalse(session.resumeHardware(from: unrelated))
        XCTAssertTrue(session.resumeHardware(from: suspension))
        XCTAssertTrue(session.allowsOrdinaryHardwareIO)

        let resumed = expectation(description: "resumed mutation admitted")
        session.runDPIOperation { _ in
            resumed.fulfill()
        } onCancelled: {
            XCTFail("exact resume must reopen ordinary mutation")
        }
        wait(for: [resumed], timeout: 1)
    }

    func testTerminalRestoreRetryUsesTheRemainingDeadlineBudget() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        var attempts = 0
        var waits = [TimeInterval]()

        let restored = LogitechTerminalHardwareRestoreRetry.perform(
            operations: [
                .init(
                    shouldContinue: { true },
                    attempt: { _ in
                        attempts += 1
                        return false
                    }
                )
            ],
            deadline: currentTime.addingTimeInterval(1),
            now: { currentTime },
            wait: { delay in
                waits.append(delay)
                currentTime.addTimeInterval(delay)
            }
        )

        XCTAssertFalse(restored)
        XCTAssertEqual(attempts, 5)
        XCTAssertEqual(waits, [0.05, 0.1, 0.2, 0.4, 0.25])
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
        XCTAssertTrue(session.hasInitialSensorDPIState)

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

    func testMultiplierOneRemainsAvailableAsValidCapability() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session)

        session.updateHiResWheelState(enabled: true, multiplier: 1, for: access)

        XCTAssertEqual(session.hiResWheelNormalizationMultiplier, 1)
    }

    func testCapabilityRefreshesProvisionalMultiplierWhileModeIsUnknown() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)
        let suspension = try XCTUnwrap(session.suspendHardware())
        XCTAssertTrue(session.resumeHardware(from: suspension))
        let resumedAccess = try hiResWheelAccess(for: session)

        session.updateHiResWheelState(enabled: nil, multiplier: 12, for: resumedAccess)

        XCTAssertNil(session.hiResWheelEnabled)
        XCTAssertEqual(session.hiResWheelNormalizationMultiplier, 12)
    }

    func testDefinitiveWheelModeClearsSuspensionMultiplier() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)
        let suspension = try XCTUnwrap(session.suspendHardware())
        XCTAssertTrue(session.resumeHardware(from: suspension))
        let resumedAccess = try hiResWheelAccess(for: session)

        session.updateHiResWheelState(enabled: false, multiplier: nil, for: resumedAccess)

        XCTAssertFalse(try XCTUnwrap(session.hiResWheelEnabled))
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
    }

    func testUnconfirmedNativeWheelStateClearsSuspensionMultiplier() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)
        let suspension = try XCTUnwrap(session.suspendHardware())
        XCTAssertTrue(session.resumeHardware(from: suspension))
        let restoreToken = session.startHiResWheelRestore { _, _ in false }

        session.clearProvisionalHiResWheelMultiplier(for: restoreToken)

        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
        session.cancelHiResWheelApply()
    }

    func testRepeatedSuspensionKeepsProvisionalMultiplierWhileModeIsUnknown() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try hiResWheelAccess(for: session)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)

        let first = try XCTUnwrap(session.suspendHardware())
        XCTAssertTrue(session.resumeHardware(from: first))
        let second = try XCTUnwrap(session.suspendHardware())

        XCTAssertNil(session.hiResWheelEnabled)
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)
        XCTAssertTrue(session.resumeHardware(from: second))
        XCTAssertEqual(session.hiResWheelNormalizationMultiplier, 8)
    }

    func testHardwareTargetChangeClearsSuspensionMultiplier() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        session.updateHiResWheelState(enabled: true, multiplier: 8, for: access)
        let suspension = try XCTUnwrap(session.suspendHardware())
        XCTAssertNil(session.hiResWheelNormalizationMultiplier)

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB034))

        XCTAssertTrue(session.resumeHardware(from: suspension))
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

    func testNewWheelDesiredCancelsRetryingStopManagingRestore() {
        let session = LogitechDeviceSession(deviceID: 1)
        let restoreToken = session.startHiResWheelRestore { _, _ in false }

        session.startHiResWheelApply { _, _ in false }

        XCTAssertTrue(restoreToken.isCancelled)
    }

    func testSupersededRestoreCannotInvalidateNewWheelAccess() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let restoreToken = session.startHiResWheelRestore { _, _ in false }
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
        XCTAssertTrue(session.hasInitialHiResWheelState)
        let reboundAccess = try hiResWheelAccess(
            for: session,
            receiverSlot: 2,
            stableTargetKey: target
        )
        XCTAssertEqual(reboundAccess.lease.stableTargetKey, target)

        _ = session.updateDiscovery(.init(identities: [], route: nil))
        _ = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        XCTAssertTrue(session.hasInitialHiResWheelState)
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

    func testStableBaselineRecoveryAfterMissingSerialRequiresReapplyAndRebinds() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let stableDiscovery = discovery(serialNumber: "AAAAAAAA", productID: 0xB034)
        _ = session.updateDiscovery(stableDiscovery)
        let target = try receiverTarget(for: stableDiscovery)
        let originalAccess = try hiResWheelAccess(
            for: session,
            receiverSlot: 2,
            stableTargetKey: target
        )
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: originalAccess))

        let incomplete = session.updateDiscovery(discovery(serialNumber: nil, productID: 0xB034))
        XCTAssertTrue(incomplete.hardwareTargetChanged)
        XCTAssertTrue(session.hasInitialHiResWheelState)
        XCTAssertNil(session.hiResWheel { _, _ in
            XCTFail("A stable baseline must remain quarantined while serial identity is missing")
            return nil
        })

        let recovered = session.updateDiscovery(stableDiscovery)
        XCTAssertTrue(recovered.hardwareTargetChanged)
        let reboundAccess = try hiResWheelAccess(
            for: session,
            receiverSlot: 2,
            stableTargetKey: target
        )
        XCTAssertEqual(session.initialHiResWheelEnabled(for: reboundAccess), false)
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

    func testMissingSerialSentinelCannotCarryBaselineToReplacementProduct() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "00000000", productID: 0xB034))
        let access = try hiResWheelAccess(for: session, receiverSlot: 2)
        XCTAssertTrue(session.recordInitialHiResWheelState(enabled: false, for: access))

        _ = session.updateDiscovery(discovery(serialNumber: "00000000", productID: 0xB035))

        XCTAssertFalse(session.hasInitialHiResWheelState)
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
        expectedToken: CancellationToken? = nil,
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
        return try XCTUnwrap(session.hiResWheel(expectedToken: expectedToken) { _, _ in
            .init(
                feature: HiResWheel(transport: transport, featureIndex: 1),
                stableTargetKey: stableTargetKey,
                receiverSlot: receiverSlot
            )
        })
    }

    private func adjustableDPIAccess(
        for session: LogitechDeviceSession,
        expectedToken: CancellationToken? = nil,
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
        return try XCTUnwrap(session.adjustableDPI(expectedToken: expectedToken) { _, _ in
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
