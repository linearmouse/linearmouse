// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechHighResolutionWheelNormalizerTests: XCTestCase {
    func testLowResolutionModeAccumulatesHighResolutionWheelUnits() throws {
        let transformer = LogitechHighResolutionWheelNormalizer(
            verticalMode: .lowResolution,
            horizontalMode: .passthrough,
            multiplier: { 8 },
            now: { 0 }
        )

        for _ in 0 ..< 3 {
            XCTAssertNil(try transformer.transform(makeVerticalScrollEvent()))
        }

        let transformedEvent = try XCTUnwrap(try transformer.transform(makeVerticalScrollEvent()))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaY, 1)
        XCTAssertEqual(view.deltaYPt, 10)
        XCTAssertEqual(view.deltaYFixedPt, 1)

        for _ in 0 ..< 4 {
            XCTAssertNil(try transformer.transform(makeVerticalScrollEvent()))
        }
    }

    func testSmoothedModeScalesHighResolutionWheelUnitsToFractionalPixels() throws {
        let transformer = LogitechHighResolutionWheelNormalizer(
            verticalMode: .smoothed,
            horizontalMode: .passthrough,
            multiplier: { 8 },
            now: { 0 }
        )

        let transformedEvent = try XCTUnwrap(try transformer.transform(makeVerticalScrollEvent()))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertTrue(view.continuous)
        XCTAssertEqual(view.deltaY, 0)
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
