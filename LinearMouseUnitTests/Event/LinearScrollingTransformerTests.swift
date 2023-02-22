// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

@testable import LinearMouse
import XCTest

class LinearScrollingTransformerTests: XCTestCase {
    func testLinearScrollingByLines() throws {
        let transformer = LinearScrollingVerticalTransformer(distance: .line(3))
        var event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 42,
            wheel2: 42,
            wheel3: 0
        )!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 3)
    }

    func testLinearScrollingByPixels() throws {
        let transformer = LinearScrollingVerticalTransformer(distance: .pixel(36))
        var event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 42,
            wheel2: 42,
            wheel3: 0
        )!
        event = transformer.transform(event)!
        let view = ScrollWheelEventView(event)
        XCTAssertTrue(view.continuous)
        XCTAssertEqual(view.deltaXPt, 0)
        XCTAssertEqual(view.deltaYPt, 36)
        XCTAssertEqual(view.deltaXFixedPt, 0)
        XCTAssertEqual(view.deltaYFixedPt, 36)
    }
}
