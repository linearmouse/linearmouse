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

    func testTargetInvalidationPermanentlyRevokesOldWorkerTeardownIO() {
        let state = LogitechReprogrammableControlsMonitorState()
        var invalidatedOwnership = false
        var madeReplacementWorker = false

        state.enable { Thread {} }
        state.invalidateTarget {
            invalidatedOwnership = true
        }

        XCTAssertTrue(invalidatedOwnership)
        XCTAssertFalse(state.shouldAllowTeardownIO)

        state.enable {
            madeReplacementWorker = true
            return Thread {}
        }
        XCTAssertFalse(madeReplacementWorker)
        XCTAssertFalse(state.shouldAllowTeardownIO)

        state.workerDidStop(restartIfEnabled: true) {
            madeReplacementWorker = true
            return Thread {}
        }
        XCTAssertTrue(madeReplacementWorker)
        XCTAssertTrue(state.shouldAllowTeardownIO)

        state.disable()
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testPendingRestoreWaitsForInvalidWorkerThenAdmitsReplacementTarget() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restored = expectation(description: "replacement target restore completed")
        var madeReplacementWorker = false

        state.enable { Thread {} }
        state.invalidateTarget {}
        let request = state.restorePendingForTeardown(
            true,
            makeWorkerThread: {
                madeReplacementWorker = true
                return Thread {}
            },
            completion: {
                restored.fulfill()
            }
        )

        XCTAssertNotNil(request)
        XCTAssertFalse(madeReplacementWorker)
        XCTAssertFalse(state.shouldAllowTeardownIO)

        state.workerDidStop(restartIfEnabled: true) {
            madeReplacementWorker = true
            return Thread {}
        }

        XCTAssertTrue(madeReplacementWorker)
        XCTAssertTrue(state.shouldAllowTeardownIO)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [restored], timeout: 1)
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

        let restoreRequest = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: {}
        )

        let reconfiguration = state.consumeReconfigurationRequest(
            deferringWhileControlsArePressed: true
        )
        XCTAssertTrue(reconfiguration.needed)
        XCTAssertTrue(reconfiguration.forced)

        guard let restoreRequest else {
            XCTFail("Expected pending restoration to start")
            return
        }
        state.expirePendingTeardownRestore(restoreRequest)
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

    func testUnkeyedRestoreStoreRejectsStaleEntryOwnershipAfterInvalidation() {
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

        XCTAssertTrue(store.replace([0x00C3: reporting], for: key, expectedOwnership: firstClaim.ownership))
        XCTAssertTrue(store.hasPending)
        XCTAssertTrue(Monitor.needsRestoreWorker(
            hasKeyedPending: false,
            hasUnkeyedPending: store.hasPending,
            hasActiveUnkeyedTarget: false
        ))
        store.invalidateAll()

        XCTAssertFalse(store.replace([0x00C3: reporting], for: key, expectedOwnership: firstClaim.ownership))
        XCTAssertTrue(store.claim(for: key).reporting.isEmpty)
        XCTAssertFalse(store.hasPending)
        XCTAssertFalse(Monitor.needsRestoreWorker(
            hasKeyedPending: false,
            hasUnkeyedPending: store.hasPending,
            hasActiveUnkeyedTarget: false
        ))
    }

    func testUnkeyedRestoreStoreRetainsEntryOwnershipWhenReportingBecomesEmpty() {
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

        XCTAssertTrue(store.replace([0x00C3: reporting], for: key, expectedOwnership: claim.ownership))
        XCTAssertTrue(store.replace([:], for: key, expectedOwnership: claim.ownership))
        XCTAssertFalse(store.hasPending)

        XCTAssertTrue(store.replace([0x00C3: reporting], for: key, expectedOwnership: claim.ownership))
        XCTAssertEqual(store.claim(for: key).reporting, [0x00C3: reporting])
    }

    func testUnkeyedRestoreStoreOwnsDifferentTargetEntriesIndependently() {
        typealias Monitor = LogitechReprogrammableControlsMonitor
        let store = Monitor.UnkeyedControlsRestoreStore()
        let firstKey = Monitor.EphemeralControlsTargetKey(
            locationID: 1,
            slot: 1,
            kind: .mouse,
            productID: 0x1234
        )
        let secondKey = Monitor.EphemeralControlsTargetKey(
            locationID: 1,
            slot: 2,
            kind: .mouse,
            productID: 0x5678
        )
        let firstReporting = Monitor.ReportingInfo(flags: [.diverted], mappedControlID: 0x00C3)
        let secondReporting = Monitor.ReportingInfo(flags: [.rawXYDiverted], mappedControlID: 0x00C4)
        let firstClaim = store.claim(for: firstKey)
        let secondClaim = store.claim(for: secondKey)

        XCTAssertNotIdentical(firstClaim.ownership, secondClaim.ownership)
        XCTAssertTrue(store.replace(
            [0x00C3: firstReporting],
            for: firstKey,
            expectedOwnership: firstClaim.ownership
        ))
        XCTAssertTrue(store.replace(
            [0x00C4: secondReporting],
            for: secondKey,
            expectedOwnership: secondClaim.ownership
        ))
        XCTAssertFalse(store.replace(
            [0x00C4: secondReporting],
            for: secondKey,
            expectedOwnership: firstClaim.ownership
        ))
        XCTAssertEqual(store.claim(for: firstKey).reporting, [0x00C3: firstReporting])
        XCTAssertEqual(store.claim(for: secondKey).reporting, [0x00C4: secondReporting])
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
        XCTAssertTrue(store.replace([0x00C3: reporting], for: key, expectedOwnership: claim.ownership))

        let state = LogitechReprogrammableControlsMonitorState()
        var madeWorker = false
        let restoreRequest = state.restorePendingForTeardown(
            store.hasPending,
            makeWorkerThread: {
                madeWorker = true
                return Thread {}
            },
            completion: {}
        )

        guard let restoreRequest else {
            XCTFail("Expected unkeyed pending restoration to start a worker")
            return
        }
        XCTAssertTrue(madeWorker)
        state.expirePendingTeardownRestore(restoreRequest)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testPendingTeardownRestoreExpiryStopsWorkerAndDeliversCompletion() {
        let state = LogitechReprogrammableControlsMonitorState()
        let completion = expectation(description: "restore timeout completion")
        guard let request = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { completion.fulfill() }
        ) else {
            XCTFail("Expected pending restoration to start")
            return
        }

        XCTAssertTrue(state.expirePendingTeardownRestore(request))
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
        guard let request = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { completion.fulfill() }
        ) else {
            XCTFail("Expected pending restoration to start")
            return
        }

        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [completion], timeout: 1)
        XCTAssertFalse(state.expirePendingTeardownRestore(request))
    }

    func testConcurrentTeardownRestoreCallersJoinOneRequestAndCompleteExactlyOnce() {
        let state = LogitechReprogrammableControlsMonitorState()
        let firstCompletion = expectation(description: "first restore caller completed")
        firstCompletion.assertForOverFulfill = true
        let secondCompletion = expectation(description: "second restore caller completed")
        secondCompletion.assertForOverFulfill = true

        guard let firstRequest = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { firstCompletion.fulfill() }
        ),
            let secondRequest = state.restorePendingForTeardown(
                true,
                makeWorkerThread: { Thread {} },
                completion: { secondCompletion.fulfill() }
            )
        else {
            XCTFail("Expected both callers to join pending restoration")
            return
        }

        XCTAssertIdentical(firstRequest, secondRequest)
        XCTAssertTrue(state.expirePendingTeardownRestore(firstRequest))
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [firstCompletion, secondCompletion], timeout: 1)
        XCTAssertFalse(state.expirePendingTeardownRestore(secondRequest))
    }

    func testOldPendingTeardownRestoreExpiryCannotCancelNewRequest() {
        let state = LogitechReprogrammableControlsMonitorState()
        let firstCompletion = expectation(description: "first timeout completion")
        guard let firstRequest = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { firstCompletion.fulfill() }
        ) else {
            XCTFail("Expected first pending restoration to start")
            return
        }

        XCTAssertTrue(state.expirePendingTeardownRestore(firstRequest))
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [firstCompletion], timeout: 1)

        let secondCompletion = expectation(description: "second timeout completion")
        guard let secondRequest = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { secondCompletion.fulfill() }
        ) else {
            XCTFail("Expected second pending restoration to start")
            return
        }

        XCTAssertFalse(state.expirePendingTeardownRestore(firstRequest))
        XCTAssertTrue(state.shouldContinueRunning)
        XCTAssertTrue(state.expirePendingTeardownRestore(secondRequest))
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [secondCompletion], timeout: 1)
    }

    func testWeakerSleepStopCannotDowngradePendingTeardownRestore() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restoreCompletion = expectation(description: "restore completed")
        restoreCompletion.assertForOverFulfill = true
        let sleepCompletion = expectation(description: "joined sleep stop completed")
        sleepCompletion.assertForOverFulfill = true

        state.enable { Thread {} }
        guard let request = state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { restoreCompletion.fulfill() }
        ) else {
            XCTFail("Expected terminal restoration to start")
            return
        }

        state.disableForSleep {
            sleepCompletion.fulfill()
        }

        XCTAssertTrue(state.shouldContinueRunning)
        XCTAssertTrue(state.shouldAllowTeardownIO)
        XCTAssertTrue(state.isRestoringPendingForTeardown)
        XCTAssertTrue(state.expirePendingTeardownRestore(request))
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [restoreCompletion, sleepCompletion], timeout: 1)
        XCTAssertFalse(state.expirePendingTeardownRestore(request))
    }

    func testQueuedSleepCompletionCannotReleaseNewTeardownRestartBarrier() {
        let state = LogitechReprogrammableControlsMonitorState()
        let sleepCompletion = expectation(description: "sleep stop completed")
        sleepCompletion.assertForOverFulfill = true
        let teardownCompletion = expectation(description: "teardown timeout completed")
        teardownCompletion.assertForOverFulfill = true

        state.enable { Thread {} }
        state.disableForSleep {
            sleepCompletion.fulfill()
        }

        // The sleep worker has stopped and queued its completion on main, but
        // that callback has not yet released the old restart barrier.
        state.workerDidStop(restartIfEnabled: true) { Thread {} }

        var madeRestoreWorker = false
        guard let request = state.restorePendingForTeardown(
            true,
            makeWorkerThread: {
                madeRestoreWorker = true
                return Thread {}
            },
            completion: {
                teardownCompletion.fulfill()
            }
        ) else {
            XCTFail("Expected terminal restoration to start")
            return
        }
        XCTAssertTrue(madeRestoreWorker)

        // Delivering the earlier sleep callback must not clear the newer
        // request's barrier or make its timeout stale.
        wait(for: [sleepCompletion], timeout: 1)
        XCTAssertTrue(state.expirePendingTeardownRestore(request))
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [teardownCompletion], timeout: 1)
        XCTAssertFalse(state.expirePendingTeardownRestore(request))
    }
}
