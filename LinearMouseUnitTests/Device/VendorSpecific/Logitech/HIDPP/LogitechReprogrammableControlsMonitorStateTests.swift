// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechReprogrammableControlsMonitorStateTests: XCTestCase {
    func testDisableStopsMonitoringButKeepsCleanupIOValidUntilWorkerStops() {
        let state = LogitechReprogrammableControlsMonitorState()

        state.enable {
            Thread {}
        }
        state.disable()

        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertTrue(state.shouldAllowTeardownIO)

        // Model the worker reaching its outer defer after it restored reporting.
        state.workerDidStop(restartIfEnabled: false) {
            Thread {}
        }

        XCTAssertFalse(state.shouldAllowTeardownIO)
    }

    func testTerminalAuthorizationImmediatelyRevokesRestoreWorkerIO() {
        let state = LogitechReprogrammableControlsMonitorState()
        let authorization = CancellationSource()

        state.enable { Thread {} }
        state.restorePendingForTeardown(
            true,
            authorization: authorization.token,
            makeWorkerThread: { Thread {} },
            completion: {}
        )
        XCTAssertFalse(state.shouldAllowTeardownIO)

        state.workerDidStop(restartIfEnabled: true) { Thread {} }
        XCTAssertTrue(state.shouldAllowTeardownIO)

        authorization.cancel()
        XCTAssertFalse(state.shouldAllowTeardownIO)

        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testAbandonStopsMonitoringWithoutPermittingTeardownIO() {
        let state = LogitechReprogrammableControlsMonitorState()

        state.enable { Thread {} }
        state.abandon()

        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertFalse(state.shouldAllowTeardownIO)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testPendingRestoreCannotBeRevivedBeforeCompletionDelivery() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restored = expectation(description: "teardown completion")
        restored.assertForOverFulfill = true
        var madeWorkerBeforeCompletion = false

        state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { restored.fulfill() }
        )
        state.workerDidStop(restartIfEnabled: false) { Thread {} }

        // The restore worker has stopped, but its lifecycle remains closed
        // until its completion is delivered on the main queue.
        state.enable {
            madeWorkerBeforeCompletion = true
            return Thread {}
        }
        XCTAssertFalse(madeWorkerBeforeCompletion)
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

    func testFastWakeResumesOnceAfterSleepRestoreBarrier() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restoreCompleted = expectation(description: "sleep reporting restore completed")
        let resumed = expectation(description: "controls resumed after sleep")
        resumed.assertForOverFulfill = true
        var resumedCount = 0
        var ordinaryWorkerCount = 0

        state.enable { Thread {} }
        state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: { restoreCompleted.fulfill() }
        )

        let resume = {
            resumedCount += 1
            state.enable {
                ordinaryWorkerCount += 1
                return Thread {}
            }
            resumed.fulfill()
        }
        state.resumeAfterSleep(resume)
        state.resumeAfterSleep(resume)

        XCTAssertEqual(resumedCount, 0)
        XCTAssertEqual(ordinaryWorkerCount, 0)
        XCTAssertFalse(state.isRestoringPendingForTeardown)
        XCTAssertFalse(state.shouldContinueRunning)

        // Fast wake cancels this monitor's restore-only transition. The exact
        // retiring worker still owns the barrier until it has safely stopped.
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [restoreCompleted, resumed], timeout: 1)

        XCTAssertEqual(resumedCount, 1)
        XCTAssertEqual(ordinaryWorkerCount, 1)

        state.disable()
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testTerminalAbandonCancelsFastWakeResume() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restoreCompleted = expectation(description: "sleep reporting restore completed")
        var resumedCount = 0

        state.enable { Thread {} }
        state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: {
                // Model a terminal upgrade delivered as the sleep barrier is
                // completing. It must still cancel the queued fast wake.
                state.abandon()
                restoreCompleted.fulfill()
            }
        )
        state.resumeAfterSleep {
            resumedCount += 1
        }

        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [restoreCompleted], timeout: 1)

        XCTAssertEqual(resumedCount, 0)
        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertFalse(state.shouldAllowTeardownIO)
    }

    func testOldSleepCompletionCannotReleaseNewSleepResume() {
        let state = LogitechReprogrammableControlsMonitorState()
        let firstRestoreCompleted = expectation(description: "first sleep restore completed")
        let secondRestoreCompleted = expectation(description: "second sleep restore completed")
        let resumed = expectation(description: "second sleep resumed")
        var resumedCount = 0

        state.enable { Thread {} }
        state.restorePendingForTeardown(
            true,
            makeWorkerThread: { Thread {} },
            completion: {
                firstRestoreCompleted.fulfill()

                // Start a new sleep lifetime from the old barrier's completion
                // delivery. Its resume must remain tied to the new barrier.
                state.cancelResumeAfterSleep()
                state.restorePendingForTeardown(
                    true,
                    makeWorkerThread: { Thread {} },
                    completion: { secondRestoreCompleted.fulfill() }
                )
                state.resumeAfterSleep {
                    resumedCount += 1
                    resumed.fulfill()
                }
            }
        )
        state.resumeAfterSleep {
            XCTFail("The first sleep resume should be cancelled by the next sleep")
        }

        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [firstRestoreCompleted], timeout: 1)
        XCTAssertEqual(resumedCount, 0)

        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [secondRestoreCompleted, resumed], timeout: 1)
        XCTAssertEqual(resumedCount, 1)
    }

    func testResumeAfterCompletedSleepIsIdempotentAtWorkerBoundary() {
        let state = LogitechReprogrammableControlsMonitorState()
        var workerCount = 0
        let resume = {
            state.enable {
                workerCount += 1
                return Thread {}
            }
        }

        state.resumeAfterSleep(resume)
        state.resumeAfterSleep(resume)

        XCTAssertEqual(workerCount, 1)

        state.disable()
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
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

    func testRestorePendingForTeardownReplacesActiveWorker() {
        let state = LogitechReprogrammableControlsMonitorState()
        var madeReplacementWorker = false
        state.enable { Thread {} }

        state.restorePendingForTeardown(
            true,
            makeWorkerThread: {
                madeReplacementWorker = true
                return Thread {}
            },
            completion: {}
        )

        XCTAssertFalse(state.shouldAllowTeardownIO)
        XCTAssertFalse(madeReplacementWorker)
        state.workerDidStop(restartIfEnabled: false) {
            madeReplacementWorker = true
            return Thread {}
        }
        XCTAssertTrue(madeReplacementWorker)
        XCTAssertTrue(state.shouldAllowTeardownIO)

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

    func testTerminalTeardownOnlyStopsWorkerThatNeverEstablishedATarget() {
        let state = LogitechReprogrammableControlsMonitorState()
        let stopped = expectation(description: "unresolved worker stopped")
        var madeRestoreWorker = false
        let unresolvedWorker = Thread {}

        state.enable { unresolvedWorker }
        state.restorePendingForTeardown(
            false,
            makeWorkerThread: {
                madeRestoreWorker = true
                return Thread {}
            },
            completion: {
                stopped.fulfill()
            }
        )

        XCTAssertFalse(madeRestoreWorker)
        XCTAssertFalse(state.shouldContinueRunning)
        XCTAssertFalse(state.shouldAllowTeardownIO)
        XCTAssertFalse(state.isRestoringPendingForTeardown)
        XCTAssertTrue(unresolvedWorker.isCancelled)

        state.workerDidStop(restartIfEnabled: true) {
            madeRestoreWorker = true
            return Thread {}
        }

        XCTAssertFalse(madeRestoreWorker)
        wait(for: [stopped], timeout: 1)
    }

    func testEstablishedUnkeyedTargetStillUsesTerminalRestoreWhenSnapshotIsStale() {
        let state = LogitechReprogrammableControlsMonitorState()
        let restored = expectation(description: "active unkeyed target restored")

        state.enable { Thread {} }
        state.setStoreBackedActiveTarget(false)

        // Model teardown taking its store snapshot just before the worker
        // publishes the active unkeyed target. The state transaction must use
        // the established target as the authoritative admission signal.
        state.restorePendingForTeardown(
            false,
            makeWorkerThread: { Thread {} },
            completion: {
                restored.fulfill()
            }
        )

        XCTAssertTrue(state.shouldContinueRunning)
        XCTAssertFalse(state.shouldAllowTeardownIO)
        XCTAssertTrue(state.isRestoringPendingForTeardown)

        state.workerDidStop(restartIfEnabled: true) { Thread {} }
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
        state.restorePendingForTeardown(
            store.hasPending,
            makeWorkerThread: {
                madeWorker = true
                return Thread {}
            },
            completion: {}
        )

        XCTAssertTrue(madeWorker)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
    }

    func testConcurrentTeardownRestoreCallersJoinOneWorkerAndCompleteExactlyOnce() {
        let state = LogitechReprogrammableControlsMonitorState()
        let firstCompletion = expectation(description: "first restore caller completed")
        firstCompletion.assertForOverFulfill = true
        let secondCompletion = expectation(description: "second restore caller completed")
        secondCompletion.assertForOverFulfill = true
        var workerCount = 0

        state.restorePendingForTeardown(
            true,
            makeWorkerThread: {
                workerCount += 1
                return Thread {}
            },
            completion: { firstCompletion.fulfill() }
        )
        state.restorePendingForTeardown(
            true,
            makeWorkerThread: {
                workerCount += 1
                return Thread {}
            },
            completion: { secondCompletion.fulfill() }
        )

        XCTAssertEqual(workerCount, 1)
        state.workerDidStop(restartIfEnabled: false) { Thread {} }
        wait(for: [firstCompletion, secondCompletion], timeout: 1)
    }
}
