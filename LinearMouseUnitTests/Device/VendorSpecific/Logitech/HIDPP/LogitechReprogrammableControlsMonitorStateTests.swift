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
}
