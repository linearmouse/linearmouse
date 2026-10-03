// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ScrollActionStateTests: XCTestCase {
    func testUniformThrottleBoundaryIsExactly300Milliseconds() {
        let throttle = ScrollActionThrottle()
        for axis: ScrollInput.Axis in [.horizontal, .vertical] {
            XCTAssertTrue(throttle.allowsAction(on: axis, at: 0))
            XCTAssertFalse(throttle.allowsAction(on: axis, at: 299_999_999))
            XCTAssertTrue(throttle.allowsAction(on: axis, at: 300_000_000))
        }
    }

    func testThrottleHasIndependentAxesAndOnlyAcceptedActionsAdvanceDeadline() {
        let throttle = ScrollActionThrottle()
        XCTAssertTrue(throttle.allowsAction(on: .horizontal, at: 0))
        XCTAssertTrue(throttle.allowsAction(on: .vertical, at: 60_000_000))
        for time: UInt64 in [1, 100, 499] {
            XCTAssertFalse(throttle.allowsAction(on: .horizontal, at: time * 600_000))
        }
        XCTAssertTrue(throttle.allowsAction(on: .horizontal, at: 300_000_000))
        XCTAssertFalse(throttle.allowsAction(on: .vertical, at: 300_000_000))
        XCTAssertTrue(throttle.allowsAction(on: .vertical, at: 360_000_000))
    }

    func testRoutesShareCooldownAndOwnershipButNeverDistanceRemainders() {
        let throttle = ScrollActionThrottle()
        let gesture = ScrollGestureOwnership()
        let first = ScrollActionRecognizer(throttle: throttle, gesture: gesture)
        let second = ScrollActionRecognizer(throttle: throttle, gesture: gesture)
        let input = ScrollInput(axis: .horizontal, delta: 4, units: .points, hasPhase: true)
        // Even identical route-local mapping indices must not combine movement.
        XCTAssertEqual(first.consume(input, mapping: 0, repeats: true, at: 0), 0)
        XCTAssertEqual(second.consume(input, mapping: 0, repeats: true, at: 1), 0)
        XCTAssertEqual(second.consume(input, mapping: 0, repeats: true, at: 2), 1)
        XCTAssertEqual(first.consume(input, mapping: 0, repeats: false, at: 3), 1)
        first.discardMovement()
        first.updateModifiers(1)
        first.updateModifiers(0)
        first.endGesture()
        XCTAssertTrue(second.ownsGesture)
        XCTAssertEqual(second.consume(input, mapping: 0, repeats: false, at: 4), 0)
        second.beginGesture()
        XCTAssertFalse(first.ownsGesture)
        XCTAssertEqual(first.consume(input, mapping: 0, repeats: false, at: 5), 0)
    }

    func testCommandMappingDiscardsPreviousScrollRemainder() {
        let recognizer = ScrollActionRecognizer()
        let input = ScrollInput(axis: .vertical, delta: 4, units: .points)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: true, at: 0), 0)
        XCTAssertEqual(recognizer.consume(input, mapping: 1, repeats: false, at: 1), 1)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: true, at: 2), 0)
    }

    func testGestureOwnershipDoesNotDependOnResolution() {
        for units: ScrollInput.Units in [.detents, .points, .lines] {
            let recognizer = ScrollActionRecognizer()
            let input = ScrollInput(axis: .vertical, delta: 0.125, units: units, hasPhase: true)
            XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 0), 1)
            recognizer.endGesture()
            XCTAssertTrue(recognizer.ownsGesture)
            recognizer.beginGesture()
            XCTAssertFalse(recognizer.ownsGesture)
        }
    }

    func testMovementDiscardAndMappingChangesDoNotCarryFractionalDistance() {
        let movement = ScrollMovementAccumulator()
        let input = ScrollInput(axis: .vertical, delta: 0.75, units: .detents)
        XCTAssertEqual(movement.consume(input, mapping: 0, at: 0), 0)
        XCTAssertEqual(movement.consume(input, mapping: 1, at: 1), 0)
        movement.discard(on: .vertical)
        XCTAssertEqual(movement.consume(input, mapping: 1, at: 2), 0)
        XCTAssertEqual(movement.consume(input, mapping: 1, at: 3), 1)
    }
}
