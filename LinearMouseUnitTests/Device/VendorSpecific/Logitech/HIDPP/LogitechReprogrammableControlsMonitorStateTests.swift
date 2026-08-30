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
}
