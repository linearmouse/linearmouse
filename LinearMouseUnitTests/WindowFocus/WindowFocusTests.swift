// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class WindowFocusTests: XCTestCase {
    func testNewUserInputDuringCompatibilityWaitPreventsOldActivation() {
        var current = true
        var deactivated = false
        var activated = false
        let result = WindowFocus.performFocus(
            switchingWithinApplication: true,
            isCurrent: { current },
            deactivate: { deactivated = true; return true },
            wait: { current = false },
            activate: { activated = true; return true }
        )
        XCTAssertFalse(result)
        XCTAssertTrue(deactivated)
        XCTAssertFalse(activated)
    }

    func testValidSameApplicationTransitionStillCompletes() {
        var actions: [String] = []
        XCTAssertTrue(WindowFocus.performFocus(
            switchingWithinApplication: true,
            isCurrent: { true },
            deactivate: { actions.append("deactivate"); return true },
            wait: { actions.append("wait") },
            activate: { actions.append("activate"); return true }
        ))
        XCTAssertEqual(actions, ["deactivate", "wait", "activate"])
    }

    func testCrossApplicationFocusDoesNotWaitOrDeactivate() {
        XCTAssertTrue(WindowFocus.performFocus(
            switchingWithinApplication: false,
            isCurrent: { true },
            deactivate: { XCTFail("Unexpected deactivation"); return false },
            wait: { XCTFail("Unexpected delay") },
            activate: { true }
        ))
    }

    func testAlreadyCancelledRequestHasNoSideEffects() {
        XCTAssertFalse(WindowFocus.performFocus(
            switchingWithinApplication: true,
            isCurrent: { false },
            deactivate: { XCTFail("Unexpected deactivation"); return false },
            wait: { XCTFail("Unexpected delay") },
            activate: { XCTFail("Unexpected activation"); return false }
        ))
    }

    func testFailedDeactivationDoesNotContinue() {
        XCTAssertFalse(WindowFocus.performFocus(
            switchingWithinApplication: true,
            isCurrent: { true },
            deactivate: { false },
            wait: { XCTFail("Unexpected delay") },
            activate: { XCTFail("Unexpected activation"); return false }
        ))
    }

    func testWakeDoesNotOverrideOtherSuspensionReasons() {
        var suspension = HoverFocusSuspension()
        suspension.sleeping = true
        suspension.screensSleeping = true
        suspension.sessionInactive = true
        suspension.sleeping = false
        XCTAssertTrue(suspension.isSuspended)
        suspension.screensSleeping = false
        XCTAssertTrue(suspension.isSuspended)
        suspension.sessionInactive = false
        XCTAssertFalse(suspension.isSuspended)
    }
}
