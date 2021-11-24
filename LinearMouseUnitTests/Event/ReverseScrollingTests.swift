//
//  ReverseScrollingTests.swift
//  LinearMouseUnitTests
//
//  Created by lujjjh on 2021/11/20.
//

import XCTest
@testable import LinearMouse

class ReverseScrollingTests: XCTestCase {
    private func assertReversed(_ transformer: EventTransformer) {
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, -2)
        XCTAssertEqual(view.deltaY, -1)
    }

    private func assertNotReversed(_ transformer: EventTransformer) {
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, 1)
    }

    func testPositive() throws {
        let transformer = ReverseScrolling(mouseDetector: FakeMouseDetector(isMouse: true))
        assertReversed(transformer)
    }

    func testNegative() throws {
        let transformer = ReverseScrolling(mouseDetector: FakeMouseDetector(isMouse: false))
        assertNotReversed(transformer)
    }
}
