// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechReprogrammableControlsMonitorStateTests: XCTestCase {
    func testDisableStopsMonitoringButKeepsCleanupIOValidUntilWorkerStops() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restored = expectation(description: "reporting restoration completed")

        state.enable {
            Thread {}
        }
        state.disable {
            restored.fulfill()
        }

        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertTrue(state.shouldAllowTeardownIO)

        // Model the worker reaching its outer defer after it restored reporting.
        state.workerDidStop(restartIfEnabled: false) {
            Thread {}
        }

        wait(for: [restored], timeout: 1)
        XCTAssertFalse(state.shouldAllowTeardownIO)
    }

    func testSleepDisableStopsMonitoringWithoutPermittingTeardownIO() {
        let state = LogitechReprogrammableControlsMonitorState()

        state.enable {
            Thread {}
        }
        state.disableForSleep()

        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertFalse(state.shouldAllowTeardownIO)

        state.workerDidStop(restartIfEnabled: false) {
            Thread {}
        }
    }

    func testAbandonStopsMonitoringWithoutPermittingTeardownIO() {
        let state = LogitechReprogrammableControlsMonitorState()

        state.enable { Thread {} }
        state.abandon()

        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertFalse(state.shouldAllowTeardownIO)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testCompletionBackedDisableCannotBeRevivedBeforeWorkerStops() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restored = expectation(description: "teardown completion")
        restored.assertForOverFulfill = true
        var madeWorkerAfterDisable = false

        state.enable {
            Thread {}
        }
        state.disable {
            restored.fulfill()
        }

        // A configuration update can race with teardown. It must not turn the
        // terminal stop into a restart and strand the completion.
        state.enable {
            madeWorkerAfterDisable = true
            return Thread {}
        }
        state.workerDidStop(restartIfEnabled: true) {
            madeWorkerAfterDisable = true
            return Thread {}
        }

        XCTAssertFalse(madeWorkerAfterDisable)
        XCTAssertFalse(state.shouldContinueRunning)

        // The worker has stopped, but the terminal lifecycle remains closed
        // until its completion is delivered on the main queue.
        state.enable {
            madeWorkerAfterDisable = true
            return Thread {}
        }
        XCTAssertFalse(madeWorkerAfterDisable)
        wait(for: [restored], timeout: 1)

        // Once completion has been delivered, a new explicit lifecycle may
        // start normally.
        var madeWorkerForNewLifecycle = false
        state.enable {
            madeWorkerForNewLifecycle = true
            return Thread {}
        }

        XCTAssertTrue(madeWorkerForNewLifecycle)
        XCTAssertTrue(state.shouldContinueRunning)

        state.disable()
        state.workerDidStop(restartIfEnabled: false) {
            Thread {}
        }
    }

    func testOrdinaryDisableCanBeReenabledBeforeWorkerStops() {
        let state = LogitechReprogrammableControlsMonitorState()
        var madeReplacementWorker = false

        state.enable {
            Thread {}
        }
        state.disable()
        state.enable {
            madeReplacementWorker = true
            return Thread {}
        }
        state.workerDidStop(restartIfEnabled: true) {
            madeReplacementWorker = true
            return Thread {}
        }

        XCTAssertTrue(madeReplacementWorker)
        XCTAssertTrue(state.shouldContinueRunning)
        XCTAssertTrue(state.shouldAllowTeardownIO)

        state.disable()
        state.workerDidStop(restartIfEnabled: false) {
            Thread {}
        }
    }

    func testRestorePendingForTeardownUpgradesSleepingWorkerAtomically() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restored = expectation(description: "pending restore drained")
        var madeReplacementWorker = false

        state.enable { Thread {} }
        state.disableForSleep()
        XCTAssertFalse(state.shouldAllowTeardownIO)

        state.restorePendingForTeardown(
            true,
            makeWorkerThread: {
                madeReplacementWorker = true
                return Thread {}
            },
            completion: {
                restored.fulfill()
            }
        )

        XCTAssertFalse(madeReplacementWorker)
        XCTAssertTrue(state.shouldContinueRunning)
        XCTAssertTrue(state.shouldAllowTeardownIO)
        XCTAssertTrue(state.isRestoringPendingForTeardown)

        // A sleeping worker has already been cancelled. It is replaced with a
        // fresh restore-only worker rather than releasing the completion.
        state.workerDidStop(restartIfEnabled: true) {
            madeReplacementWorker = true
            return Thread {}
        }
        XCTAssertTrue(madeReplacementWorker)

        // The replacement reaches this point only after it observed no
        // pending baseline, so completion cannot race ahead of restoration.
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [restored], timeout: 1)
    }

    func testRestorePendingForTeardownForcesActiveWorkerToOuterLoop() {
        let state = LogitechReprogrammableControlsMonitorState()
        state.enable { Thread {} }

        let generation = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: {}
        )

        let request = state.consumeReconfigurationRequest(
            deferringWhileControlsArePressed: true
        )
        XCTAssertTrue(request.needed)
        XCTAssertTrue(request.forced)

        guard let generation else {
            XCTFail("Expected pending restoration to start")
            return
        }
        state.expirePendingTeardownRestore(generation)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testRestorePendingForTeardownStartsWorkerOnlyWhenBaselineExists() {
        let state = LogitechReprogrammableControlsMonitorState()
        let noWorkCompletion = expectation(description: "no pending baseline")
        var madeWorker = false

        state.restorePendingForTeardown(
            false,
            makeWorkerThread: {
                madeWorker = true
                return Thread {}
            },
            completion: {
                noWorkCompletion.fulfill()
            }
        )

        XCTAssertFalse(madeWorker)
        wait(for: [noWorkCompletion], timeout: 1)

        let restored = expectation(description: "pending baseline restored")
        state.restorePendingForTeardown(
            true,
            makeWorkerThread: {
                madeWorker = true
                return Thread {}
            },
            completion: {
                restored.fulfill()
            }
        )

        XCTAssertTrue(madeWorker)
        XCTAssertTrue(state.shouldAllowTeardownIO)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [restored], timeout: 1)
    }

    func testRetryWaitReturnsAfterTimeout() {
        let state = LogitechReprogrammableControlsMonitorState()
        state.enable { Thread {} }

        let result = state.waitForReconfigurationOrRetryTimeout(timeout: 0)
        XCTAssertTrue(result.shouldContinue)
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.forced)

        state.disable()
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testOnlyActiveUnkeyedTargetKeepsRestoreWorkerAdmitted() {
        let state = LogitechReprogrammableControlsMonitorState()
        state.enable { Thread {} }

        XCTAssertFalse(state.hasActiveUnkeyedTarget)
        state.setStoreBackedActiveTarget(false)
        XCTAssertTrue(state.hasActiveUnkeyedTarget)
        XCTAssertTrue(LogitechReprogrammableControlsMonitor.needsRestoreWorker(
            hasKeyedPending: false,
            hasUnkeyedPending: false,
            hasActiveUnkeyedTarget: state.hasActiveUnkeyedTarget
        ))

        state.setStoreBackedActiveTarget(true)
        XCTAssertFalse(state.hasActiveUnkeyedTarget)
        XCTAssertFalse(LogitechReprogrammableControlsMonitor.needsRestoreWorker(
            hasKeyedPending: false,
            hasUnkeyedPending: false,
            hasActiveUnkeyedTarget: state.hasActiveUnkeyedTarget
        ))

        state.disable()
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testUnkeyedRestoreStoreRejectsStaleGenerationWrites() {
        typealias Monitor = LogitechReprogrammableControlsMonitor
        let store = Monitor.UnkeyedControlsRestoreStore()
        let key = Monitor.EphemeralControlsTargetKey(
            locationID: 1,
            slot: 2,
            kind: .mouse,
            productID: 0x1234
        )
        let reporting = Monitor.ReportingInfo(flags: [.diverted], mappedControlID: 0x00C3)
        let firstClaim = store.claim(for: key)

        XCTAssertTrue(store.replace([0x00C3: reporting], for: key, expectedGeneration: firstClaim.generation))
        XCTAssertTrue(store.hasPending)
        XCTAssertTrue(Monitor.needsRestoreWorker(
            hasKeyedPending: false,
            hasUnkeyedPending: store.hasPending,
            hasActiveUnkeyedTarget: false
        ))
        store.invalidateAll()

        XCTAssertFalse(store.replace([0x00C3: reporting], for: key, expectedGeneration: firstClaim.generation))
        XCTAssertTrue(store.claim(for: key).reporting.isEmpty)
        XCTAssertFalse(store.hasPending)
        XCTAssertFalse(Monitor.needsRestoreWorker(
            hasKeyedPending: false,
            hasUnkeyedPending: store.hasPending,
            hasActiveUnkeyedTarget: false
        ))
    }

    func testPendingUnkeyedRestoreStartsWorkerAfterMonitorStopped() {
        typealias Monitor = LogitechReprogrammableControlsMonitor
        let store = Monitor.UnkeyedControlsRestoreStore()
        let key = Monitor.EphemeralControlsTargetKey(
            locationID: 1,
            slot: 2,
            kind: .mouse,
            productID: 0x1234
        )
        let reporting = Monitor.ReportingInfo(flags: [.diverted], mappedControlID: 0x00C3)
        let claim = store.claim(for: key)
        XCTAssertTrue(store.replace([0x00C3: reporting], for: key, expectedGeneration: claim.generation))

        let state = LogitechReprogrammableControlsMonitorState()
        var madeWorker = false
        let restoreGeneration = state.restorePendingForTeardown(
            store.hasPending,
            makeWorkerThread: {
                madeWorker = true
                return Thread {}
            },
            completion: {}
        )

        guard let restoreGeneration else {
            XCTFail("Expected unkeyed pending restoration to start a worker")
            return
        }
        XCTAssertTrue(madeWorker)
        state.expirePendingTeardownRestore(restoreGeneration)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testPendingTeardownRestoreExpiryStopsWorkerAndDeliversCompletion() {
        let state = LogitechReprogrammableControlsMonitorState()
        let completion = expectation(description: "restore timeout completion")
        guard let generation = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { completion.fulfill() }
        ) else {
            XCTFail("Expected pending restoration to start")
            return
        }

        XCTAssertTrue(state.expirePendingTeardownRestore(generation))
        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertFalse(state.shouldAllowTeardownIO)

        // Model a worker which never resolved a target and only now observes
        // cancellation from the expiry path.
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [completion], timeout: 1)
    }

    func testCompletedPendingTeardownRestoreIgnoresLateExpiry() {
        let state = LogitechReprogrammableControlsMonitorState()
        let completion = expectation(description: "restore completion")
        guard let generation = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { completion.fulfill() }
        ) else {
            XCTFail("Expected pending restoration to start")
            return
        }

        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [completion], timeout: 1)
        XCTAssertFalse(state.expirePendingTeardownRestore(generation))
    }

    func testOldPendingTeardownRestoreExpiryCannotCancelNewRequest() {
        let state = LogitechReprogrammableControlsMonitorState()
        let firstCompletion = expectation(description: "first timeout completion")
        guard let firstGeneration = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { firstCompletion.fulfill() }
        ) else {
            XCTFail("Expected first pending restoration to start")
            return
        }

        XCTAssertTrue(state.expirePendingTeardownRestore(firstGeneration))
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [firstCompletion], timeout: 1)

        let secondCompletion = expectation(description: "second timeout completion")
        guard let secondGeneration = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { secondCompletion.fulfill() }
        ) else {
            XCTFail("Expected second pending restoration to start")
            return
        }

        XCTAssertFalse(state.expirePendingTeardownRestore(firstGeneration))
        XCTAssertTrue(state.shouldContinueRunning)
        XCTAssertTrue(state.expirePendingTeardownRestore(secondGeneration))
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [secondCompletion], timeout: 1)
    }
}
