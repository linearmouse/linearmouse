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
        event = try XCTUnwrap(transformer.transform(event, in: .init(device: nil)))
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
        event = try XCTUnwrap(transformer.transform(event, in: .init(device: nil)))
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
            highResolutionWheelMultiplier: { _ in 8 },
            now: { 0 }
        )
        let context = EventTransformerContext(device: nil)

        for _ in 0 ..< 3 {
            XCTAssertNil(try transformer.transform(makeVerticalHighResolutionScrollEvent(), in: context))
        }

        let transformedEvent = try XCTUnwrap(try transformer.transform(
            makeVerticalHighResolutionScrollEvent(),
            in: context
        ))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 3)
    }

    func testHighResolutionWheelPixelScrollingUsesMultiplier() throws {
        let transformer = LinearScrollingVerticalTransformer(
            distance: .pixel(36),
            highResolutionWheelMultiplier: { _ in 8 },
            now: { 0 }
        )
        let context = EventTransformerContext(device: nil)

        let transformedEvent = try XCTUnwrap(try transformer.transform(
            makeVerticalHighResolutionScrollEvent(),
            in: context
        ))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertTrue(view.continuous)
        XCTAssertEqual(view.deltaXFixedPt, 0)
        XCTAssertGreaterThan(view.deltaYPt, 0)
        XCTAssertLessThan(view.deltaYPt, 36)
        XCTAssertEqual(view.deltaYFixedPt, 4.5, accuracy: 0.001)
    }

    func testHighResolutionWheelMultiplierIsResolvedAtTransformTime() throws {
        var multiplier = 8
        let transformer = LinearScrollingVerticalTransformer(
            distance: .pixel(36),
            highResolutionWheelMultiplier: { _ in multiplier },
            now: { 0 }
        )
        let context = EventTransformerContext(device: nil)

        let multiplier8Event = try XCTUnwrap(try transformer.transform(
            makeVerticalHighResolutionScrollEvent(multiplier: 8),
            in: context
        ))
        multiplier = 4
        let multiplier4Event = try XCTUnwrap(try transformer.transform(
            makeVerticalHighResolutionScrollEvent(multiplier: 4),
            in: context
        ))

        XCTAssertEqual(ScrollWheelEventView(multiplier8Event).deltaYFixedPt, 4.5, accuracy: 0.001)
        XCTAssertEqual(ScrollWheelEventView(multiplier4Event).deltaYFixedPt, 9, accuracy: 0.001)
    }

    func testHighResolutionWheelPixelScrollingUsesFixedPointUnitsWhenIntegerDeltaIsCoalesced() throws {
        let transformer = LinearScrollingVerticalTransformer(
            distance: .pixel(36),
            highResolutionWheelMultiplier: { _ in 10 },
            now: { 0 }
        )
        let context = EventTransformerContext(device: nil)

        let transformedEvent = try XCTUnwrap(try transformer.transform(
            makeVerticalHighResolutionScrollEvent(multiplier: 10, units: 17.390899658203125),
            in: context
        ))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertTrue(view.continuous)
        XCTAssertEqual(view.deltaXFixedPt, 0)
        XCTAssertEqual(view.deltaYPt, 62, accuracy: 0.001)
        XCTAssertEqual(view.deltaYFixedPt, 62.60723876953125, accuracy: 0.001)
    }

    func testHighResolutionWheelLinearDistanceShouldUseRawUnitsWhenAccelerationIsPresent() {
        let resolution = LogitechHighResolutionWheelUnitReader.units(
            integerDelta: 14,
            pointDelta: 140,
            fixedPointDelta: 13.943,
            ioHidDelta: -1,
            signum: 1,
            multiplier: 8
        )
        let pixelDistance = abs(resolution.rawUnits) * 36 / 8

        XCTAssertEqual(resolution.rawUnits, 1, accuracy: 0.001)
        XCTAssertEqual(resolution.units, 14, accuracy: 0.001)
        XCTAssertEqual(pixelDistance, 4.5, accuracy: 0.001)
    }

    private func makeVerticalHighResolutionScrollEvent(
        multiplier: Int = 8,
        units: Double = 1
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(units.sign == .minus ? -1 : 1),
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.deltaYFixedPt = units / Double(multiplier)
        view.deltaYPt = units * 10 / Double(multiplier)
        return event
    }
}
