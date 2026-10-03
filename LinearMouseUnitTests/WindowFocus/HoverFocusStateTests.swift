// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class HoverFocusStateTests: XCTestCase {
    private let first = HoverFocusState.Target(windowID: 10, pid: 1, senderID: 7)
    private let second = HoverFocusState.Target(windowID: 11, pid: 1, senderID: 7)

    func testWindowEntryIsReadyWithoutWaitingForAnotherSample() {
        var state = HoverFocusState()
        XCTAssertTrue(state.update(first))
        state.suspend()
        XCTAssertTrue(state.update(second))
    }

    func testCompletedEntryDoesNotRepeatedlyFocus() {
        var state = HoverFocusState()
        XCTAssertTrue(state.update(first))
        state.suspend()
        XCTAssertFalse(state.update(first))
        XCTAssertFalse(state.isWaiting)
    }

    func testKeyboardClickOrSpaceChangeRequiresReentry() {
        var state = HoverFocusState()
        _ = state.update(first)
        state.suspend()
        XCTAssertFalse(state.update(first))
        XCTAssertTrue(state.update(second))
        state.suspend()
        XCTAssertTrue(state.update(first))
    }

    func testOverlayOrExcludedApplicationClearsPendingFocus() {
        var state = HoverFocusState()
        _ = state.update(first)
        XCTAssertFalse(state.update(nil))
        XCTAssertFalse(state.isWaiting)
        XCTAssertTrue(state.update(first))
    }

    func testSwitchingPhysicalDevicesStartsNewEntry() {
        var state = HoverFocusState()
        _ = state.update(first)
        state.suspend()
        let anotherDevice = HoverFocusState.Target(windowID: 10, pid: 1, senderID: 8)
        XCTAssertTrue(state.update(anotherDevice))
    }
}
