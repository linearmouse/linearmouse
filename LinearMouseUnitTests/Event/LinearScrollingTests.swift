//
//  LinearScrollingTests.swift
//  LinearMouseUnitTests
//
//  Created by lujjjh on 2021/11/24.
//

import XCTest
@testable import LinearMouse

class LinearScrollingTests: XCTestCase {
    func testLinearScrolling() throws {
        let transformer = LinearScrolling(scrollLines: 3)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 42, wheel2: 42, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 3)
        XCTAssertEqual(view.deltaY, 3)
    }
}
