// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class HoverFocusStateTests: XCTestCase {
    private let first = HoverFocusState.Target(windowID: 10, pid: 1, senderID: 7)
    private let second = HoverFocusState.Target(windowID: 11, pid: 1, senderID: 7)

    func testCrossingWindowDoesNotFocusAndDwellIsPerWindow() {
        var state = HoverFocusState()
        XCTAssertFalse(state.update(first, now: 0))
        XCTAssertFalse(state.update(first, now: 0.09))
        XCTAssertFalse(state.update(second, now: 0.095))
        XCTAssertFalse(state.update(second, now: 0.15))
        XCTAssertTrue(state.update(second, now: 0.20))
    }

    func testCompletedEntryDoesNotRepeatedlyFocus() {
        var state = HoverFocusState()
        XCTAssertFalse(state.update(first, now: 0))
        XCTAssertTrue(state.update(first, now: 0.11))
        state.suspend()
        XCTAssertFalse(state.update(first, now: 10))
        XCTAssertFalse(state.isWaiting)
    }

    func testKeyboardClickOrSpaceChangeRequiresReentry() {
        var state = HoverFocusState()
        _ = state.update(first, now: 0)
        state.suspend()
        XCTAssertFalse(state.update(first, now: 0.2))
        XCTAssertFalse(state.update(first, now: 20))
        XCTAssertFalse(state.update(second, now: 21))
        XCTAssertTrue(state.update(second, now: 21.2))
        XCTAssertFalse(state.update(first, now: 22))
        XCTAssertTrue(state.update(first, now: 22.2))
    }

    func testOverlayOrExcludedApplicationCancelsDwell() {
        var state = HoverFocusState()
        _ = state.update(first, now: 0)
        XCTAssertFalse(state.update(nil, now: 0.09))
        XCTAssertFalse(state.update(first, now: 1))
        XCTAssertFalse(state.update(first, now: 1.05))
        XCTAssertTrue(state.update(first, now: 1.2))
    }

    func testSwitchingPhysicalDevicesStartsNewDwell() {
        var state = HoverFocusState()
        _ = state.update(first, now: 0)
        let anotherDevice = HoverFocusState.Target(windowID: 10, pid: 1, senderID: 8)
        XCTAssertFalse(state.update(anotherDevice, now: 0.09))
        XCTAssertFalse(state.update(anotherDevice, now: 0.15))
        XCTAssertTrue(state.update(anotherDevice, now: 0.2))
    }
}
