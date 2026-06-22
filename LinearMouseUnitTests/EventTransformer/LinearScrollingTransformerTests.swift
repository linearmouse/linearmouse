// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LinearScrollingTransformerTests: XCTestCase {
    func testLinearScrollingByLines() throws {
        let transformer = LinearScrollingVerticalTransformer(distance: .line(3))
        var event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 42,
            wheel2: 42,
            wheel3: 0
        ))
        event = try XCTUnwrap(transformer.transform(event))
        let view = ScrollWheelEventView(event)
        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 3)
    }

    func testLinearScrollingByPixels() throws {
        let transformer = LinearScrollingVerticalTransformer(distance: .pixel(36))
        var event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 42,
            wheel2: 42,
            wheel3: 0
        ))
        event = try XCTUnwrap(transformer.transform(event))
        let view = ScrollWheelEventView(event)
        XCTAssertTrue(view.continuous)
        XCTAssertEqual(view.deltaXPt, 0)
        XCTAssertEqual(view.deltaYPt, 36)
        XCTAssertEqual(view.deltaXFixedPt, 0)
        XCTAssertEqual(view.deltaYFixedPt, 36)
    }

    func testHighResolutionWheelLineScrollingUsesMultiplier() throws {
        let transformer = LinearScrollingVerticalTransformer(
            distance: .line(3),
            highResolutionWheelMultiplier: { 8 },
            now: { 0 }
        )

        for _ in 0 ..< 3 {
            XCTAssertNil(try transformer.transform(makeVerticalScrollEvent()))
        }

        let transformedEvent = try XCTUnwrap(try transformer.transform(makeVerticalScrollEvent()))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 3)
    }

    func testHighResolutionWheelPixelScrollingUsesMultiplier() throws {
        let transformer = LinearScrollingVerticalTransformer(
            distance: .pixel(36),
            highResolutionWheelMultiplier: { 8 },
            now: { 0 }
        )

        let transformedEvent = try XCTUnwrap(try transformer.transform(makeVerticalScrollEvent()))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertTrue(view.continuous)
        XCTAssertEqual(view.deltaXFixedPt, 0)
        XCTAssertGreaterThan(view.deltaYPt, 0)
        XCTAssertLessThan(view.deltaYPt, 36)
        XCTAssertEqual(view.deltaYFixedPt, 4.5, accuracy: 0.001)
    }

    private func makeVerticalScrollEvent() throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
    }
}
