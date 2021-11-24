//
//  LinearScrollingTests.swift
//  LinearMouseUnitTests
//
//  Created by lujjjh on 2021/11/24.
//

import XCTest
@testable import LinearMouse

class LinearScrollingTests: XCTestCase {
    private func assertChanged(_ transformer: EventTransformer) {
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 42, wheel2: 42, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 3)
        XCTAssertEqual(view.deltaY, 3)
    }

    private func assertNotChanged(_ transformer: EventTransformer) {
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 42, wheel2: 42, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 42)
        XCTAssertEqual(view.deltaY, 42)
    }

    func testPositive() throws {
        let transformer = LinearScrolling(mouseDetector: FakeMouseDetector(isMouse: true), scrollLines: 3)
        assertChanged(transformer)
    }

    func testNegative() throws {
        let transformer = LinearScrolling(mouseDetector: FakeMouseDetector(isMouse: false), scrollLines: 3)
        assertNotChanged(transformer)
    }
}
