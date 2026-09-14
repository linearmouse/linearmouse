// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import GestureKit
import XCTest

final class GestureSendabilityTests: XCTestCase {
    private struct GestureParameters: Sendable {
        let phase: CGSGesturePhase
        let direction: IOHIDSwipeMask
    }

    func testParametersCanBeSharedWithAnEventProducingQueue() {
        let parameters = GestureParameters(phase: .began, direction: .swipeLeft)
        let completed = expectation(description: "Gesture events created on another queue")

        DispatchQueue.global().async {
            XCTAssertEqual(parameters.phase.rawValue, 1)
            XCTAssertEqual(parameters.direction.rawValue, 4)
            XCTAssertNotNil(GestureEvent(
                navigationSwipeSource: nil,
                direction: parameters.direction
            ))
            XCTAssertNotNil(GestureEvent(
                scrollSource: nil,
                phase: parameters.phase,
                deltaX: 4,
                deltaY: -2
            ))
            completed.fulfill()
        }

        // Only the parameters are shared; the mutable events stay on their queue.
        XCTAssertEqual(parameters.phase, .began)
        XCTAssertEqual(parameters.direction, .swipeLeft)
        wait(for: [completed], timeout: 2)
    }
}
