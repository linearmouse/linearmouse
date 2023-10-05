// MIT License
// Copyright (c) 2021-2024 LinearMouse

@testable import LinearMouse
import XCTest

class ReverseScrollingTransformerTests: XCTestCase {
    func testReverseScrollingVertically() throws {
        let transformer = ReverseScrollingTransformer(vertically: true)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, -1)
    }

    func testReverseScrollingHorizontally() throws {
        let transformer = ReverseScrollingTransformer(horizontally: true)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, -2)
        XCTAssertEqual(view.deltaY, 1)
    }
}
