// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class SmoothedScrollingTransformerTests: XCTestCase {
    func testSmoothedScrollingPreservesUnsmoothedAxisAndEmitsSyntheticEvent() throws {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(
                vertical: .init(
                    enabled: true,
                    preset: .natural,
                    response: Decimal(string: "0.45"),
                    speed: 1,
                    acceleration: Decimal(string: "1.2"),
                    inertia: Decimal(string: "0.65")
                )
            ),
            now: { now },
            eventSink: { emittedEvents.append($0.copy() ?? $0) }
        )

        let originalEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 2,
            wheel2: 3,
            wheel3: 0
        ))
        originalEvent.flags = [.maskAlternate]

        let passthroughEvent = try XCTUnwrap(transformer.transform(originalEvent))
        let passthroughView = ScrollWheelEventView(passthroughEvent)
        XCTAssertEqual(passthroughView.deltaX, 3)
        XCTAssertEqual(passthroughView.deltaY, 0)

        now = 1.0 / 120.0
        transformer.tick()

        let emittedEvent = try XCTUnwrap(emittedEvents.first)
        let emittedView = ScrollWheelEventView(emittedEvent)
        XCTAssertTrue(emittedEvent.isLinearMouseSyntheticEvent)
        XCTAssertEqual(emittedView.deltaX, 0)
        XCTAssertEqual(emittedView.scrollPhase, .began)
        XCTAssertEqual(emittedView.momentumPhase, .none)
        XCTAssertGreaterThan(abs(emittedView.deltaYPt), 0)
        XCTAssertEqual(emittedEvent.flags, [.maskAlternate])
    }

    func testDiscreteWheelInputUsesLineDeltaForStartupEvenWhenPointDeltaExists() throws {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(
                vertical: Scheme.Scrolling.Smoothed.Preset.spring.defaultConfiguration
            ),
            now: { now },
            eventSink: { emittedEvents.append($0.copy() ?? $0) }
        )

        let originalEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let originalView = ScrollWheelEventView(originalEvent)
        originalView.deltaYPt = 1
        originalView.deltaYFixedPt = 0.1
        XCTAssertFalse(originalView.continuous)

        XCTAssertNil(transformer.transform(originalEvent))

        now = 1.0 / 120.0
        transformer.tick()

        let emittedEvent = try XCTUnwrap(emittedEvents.first)
        let emittedView = ScrollWheelEventView(emittedEvent)
        XCTAssertGreaterThan(abs(emittedView.deltaYPt), 3)
        XCTAssertEqual(emittedView.scrollPhase, .began)
    }

    func testContinuousTrackpadInputWithNativePhaseIsSmoothedInPlace() throws {
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(
                vertical: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration
            )
        ) {
            now
        }

        let originalEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        let originalView = ScrollWheelEventView(originalEvent)
        originalView.continuous = true
        originalView.deltaYPt = 9
        originalView.deltaYFixedPt = 9
        originalView.scrollPhase = .began

        let transformedEvent = try XCTUnwrap(transformer.transform(originalEvent))
        let transformedView = ScrollWheelEventView(transformedEvent)
        XCTAssertEqual(transformedView.deltaYPt, 1, accuracy: 0.001)
        XCTAssertGreaterThan(transformedView.deltaYFixedPt, 0)
        XCTAssertLessThan(transformedView.deltaYFixedPt, 9)
        XCTAssertEqual(transformedView.scrollPhase, .began)
    }
}
