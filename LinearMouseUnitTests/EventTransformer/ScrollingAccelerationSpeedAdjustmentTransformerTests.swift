// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ScrollingAccelerationSpeedAdjustmentTransformerTests: XCTestCase {
    /// The fixed-point delta fields are stored as 16.16 fixed point; allow for one
    /// quantization step when comparing against the expected value.
    private let fixedPointTolerance = 1.0 / 32_768.0

    func testSpeedAdjustmentKeepsContinuousFixedPointInPixelSpace() throws {
        // A continuous (pixel-mode) scroll event carries its delta in pixel units: both
        // deltaYPt and deltaYFixedPt hold the same pixel value.
        let transformer = ScrollingAccelerationSpeedAdjustmentTransformer(
            acceleration: Scheme.Scrolling.Bidirectional<Decimal>(vertical: nil, horizontal: nil),
            speed: Scheme.Scrolling.Bidirectional<Decimal>(vertical: 3, horizontal: nil)
        )

        let event = try makeVerticalScrollEvent(
            continuous: true,
            deltaY: 0,
            deltaYPt: 5,
            deltaYFixedPt: 5
        )

        let result = try XCTUnwrap(
            transformer.transform(event, in: EventTransformerContext(device: nil))
        )

        let view = ScrollWheelEventView(result)

        // targetPt = 5 + sign(5) * 3 = 8 px. For a continuous event the fixed-point
        // delta must stay in pixel space (8), not be divided into line units (0.8).
        XCTAssertEqual(view.deltaYPt, 8, accuracy: fixedPointTolerance)
        XCTAssertEqual(view.deltaYFixedPt, 8, accuracy: fixedPointTolerance)
    }

    func testSpeedAdjustmentKeepsDiscreteFixedPointInLineSpace() throws {
        // A discrete (line-mode) scroll event carries its fixed-point delta in line units.
        let transformer = ScrollingAccelerationSpeedAdjustmentTransformer(
            acceleration: Scheme.Scrolling.Bidirectional<Decimal>(vertical: nil, horizontal: nil),
            speed: Scheme.Scrolling.Bidirectional<Decimal>(vertical: 3, horizontal: nil)
        )

        let event = try makeVerticalScrollEvent(
            continuous: false,
            deltaY: 1,
            deltaYPt: 10,
            deltaYFixedPt: 1
        )

        let result = try XCTUnwrap(
            transformer.transform(event, in: EventTransformerContext(device: nil))
        )

        let view = ScrollWheelEventView(result)

        // targetPt = 10 + sign(1) * 3 = 13 px. The discrete fixed-point delta stays in
        // line units (13 / 10 = 1.3); the discrete path must remain unchanged.
        XCTAssertEqual(view.deltaYPt, 13, accuracy: fixedPointTolerance)
        XCTAssertEqual(view.deltaYFixedPt, 1.3, accuracy: fixedPointTolerance)
    }

    func testAccelerationScalesAllDeltasUniformly() throws {
        // The acceleration path scales every delta field by the same factor, which is
        // correct for both continuous and discrete events; only the speed path needed
        // the mode-aware fixed-point fix.
        let transformer = ScrollingAccelerationSpeedAdjustmentTransformer(
            acceleration: Scheme.Scrolling.Bidirectional<Decimal>(vertical: 2, horizontal: nil),
            speed: Scheme.Scrolling.Bidirectional<Decimal>(vertical: nil, horizontal: nil)
        )

        let event = try makeVerticalScrollEvent(
            continuous: true,
            deltaY: 1,
            deltaYPt: 5,
            deltaYFixedPt: 5
        )

        let result = try XCTUnwrap(
            transformer.transform(event, in: EventTransformerContext(device: nil))
        )

        let view = ScrollWheelEventView(result)

        XCTAssertEqual(view.deltaYPt, 10, accuracy: fixedPointTolerance)
        XCTAssertEqual(view.deltaYFixedPt, 10, accuracy: fixedPointTolerance)
    }

    func testSpeedAdjustmentKeepsContinuousHorizontalFixedPointInPixelSpace() throws {
        // Same as the vertical case but on the horizontal axis: a continuous event's
        // deltaXFixedPt must stay in pixel space, not be divided into line units.
        let transformer = ScrollingAccelerationSpeedAdjustmentTransformer(
            acceleration: Scheme.Scrolling.Bidirectional<Decimal>(vertical: nil, horizontal: nil),
            speed: Scheme.Scrolling.Bidirectional<Decimal>(vertical: nil, horizontal: 3)
        )

        let event = try makeHorizontalScrollEvent(
            continuous: true,
            deltaX: 0,
            deltaXPt: 5,
            deltaXFixedPt: 5
        )

        let result = try XCTUnwrap(
            transformer.transform(event, in: EventTransformerContext(device: nil))
        )

        let view = ScrollWheelEventView(result)

        // targetPt = 5 + sign(5) * 3 = 8 px; the horizontal fixed-point delta stays in pixels.
        XCTAssertEqual(view.deltaXPt, 8, accuracy: fixedPointTolerance)
        XCTAssertEqual(view.deltaXFixedPt, 8, accuracy: fixedPointTolerance)
    }

    private func makeVerticalScrollEvent(
        continuous: Bool,
        deltaY: Int64,
        deltaYPt: Double,
        deltaYFixedPt: Double
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: continuous ? .pixel : .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.continuous = continuous
        view.deltaY = deltaY
        view.deltaYPt = deltaYPt
        view.deltaYFixedPt = deltaYFixedPt
        view.deltaX = 0
        view.deltaXPt = 0
        view.deltaXFixedPt = 0
        return event
    }

    private func makeHorizontalScrollEvent(
        continuous: Bool,
        deltaX: Int64,
        deltaXPt: Double,
        deltaXFixedPt: Double
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: continuous ? .pixel : .line,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 1,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.continuous = continuous
        view.deltaX = deltaX
        view.deltaXPt = deltaXPt
        view.deltaXFixedPt = deltaXFixedPt
        view.deltaY = 0
        view.deltaYPt = 0
        view.deltaYFixedPt = 0
        return event
    }
}
