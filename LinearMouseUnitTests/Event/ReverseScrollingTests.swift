// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

@testable import LinearMouse
import XCTest

class ReverseScrollingTests: XCTestCase {
    func testReverseScrollingVertically() throws {
        let transformer = ReverseScrolling(vertically: true)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, -1)
    }

    func testReverseScrollingHorizontally() throws {
        let transformer = ReverseScrolling(horizontally: true)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, -2)
        XCTAssertEqual(view.deltaY, 1)
    }
}
