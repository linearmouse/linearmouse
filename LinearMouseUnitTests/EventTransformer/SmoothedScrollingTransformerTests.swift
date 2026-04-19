// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class SmoothedScrollingTransformerTests: XCTestCase {
    func testModifierAlterOrientationAppliesBeforeDiscreteSmoothedScrolling() throws {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let modifiers = Scheme.Scrolling.Modifiers(shift: .alterOrientation)
        let smoothedTransformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: Scheme.Scrolling.Smoothed.Preset.smooth.defaultConfiguration),
            now: { now },
            eventSink: { emittedEvents.append($0.copy() ?? $0) }
        )
        let transformer: [EventTransformer] = [
            ModifierActionsTransformer(modifiers: .init(vertical: modifiers, horizontal: modifiers)),
            smoothedTransformer
        ]

        let originalEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        originalEvent.flags = [.maskShift]

        let transformedEvent = try XCTUnwrap(transformer.transform(originalEvent))
        let transformedView = ScrollWheelEventView(transformedEvent)
        XCTAssertEqual(transformedView.deltaX, 1)
        XCTAssertEqual(transformedView.deltaY, 0)
        XCTAssertEqual(transformedEvent.flags, [])

        now = 1.0 / 120.0
        smoothedTransformer.tick()
        XCTAssertTrue(emittedEvents.isEmpty)
    }

    func testModifierChangeSpeedAppliesBeforeDiscreteSmoothedScrolling() throws {
        var baselineEmittedEvents: [CGEvent] = []
        var scaledEmittedEvents: [CGEvent] = []
        var now = 0.0
        let modifiers = Scheme.Scrolling.Modifiers(option: .changeSpeed(scale: 2))

        let baselineTransformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: Scheme.Scrolling.Smoothed.Preset.smooth.defaultConfiguration),
            now: { now },
            eventSink: { baselineEmittedEvents.append($0.copy() ?? $0) }
        )
        let scaledTransformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: Scheme.Scrolling.Smoothed.Preset.smooth.defaultConfiguration),
            now: { now },
            eventSink: { scaledEmittedEvents.append($0.copy() ?? $0) }
        )

        let baselineChain: [EventTransformer] = [
            ModifierActionsTransformer(modifiers: .init(vertical: modifiers, horizontal: modifiers)),
            baselineTransformer
        ]
        let scaledChain: [EventTransformer] = [
            ModifierActionsTransformer(modifiers: .init(vertical: modifiers, horizontal: modifiers)),
            scaledTransformer
        ]

        let baselineEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let scaledEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        scaledEvent.flags = [.maskAlternate]

        XCTAssertNil(baselineChain.transform(baselineEvent))
        XCTAssertNil(scaledChain.transform(scaledEvent))

        now = 1.0 / 120.0
        baselineTransformer.tick()
        scaledTransformer.tick()

        let baselineView = try ScrollWheelEventView(XCTUnwrap(baselineEmittedEvents.first))
        let scaledView = try ScrollWheelEventView(XCTUnwrap(scaledEmittedEvents.first))
        XCTAssertGreaterThan(abs(scaledView.deltaYPt), abs(baselineView.deltaYPt))
    }

    func testShiftOrientationSwitchClearsPreviousAxisMomentum() throws {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let modifiers = Scheme.Scrolling.Modifiers(shift: .alterOrientation)
        let smoothedTransformer = SmoothedScrollingTransformer(
            smoothed: .init(
                vertical: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration,
                horizontal: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration
            ),
            now: { now },
            eventSink: { emittedEvents.append($0.copy() ?? $0) }
        )
        let transformer: [EventTransformer] = [
            ModifierActionsTransformer(modifiers: .init(vertical: modifiers, horizontal: modifiers)),
            smoothedTransformer
        ]

        for step in 0 ..< 6 {
            let event = try XCTUnwrap(CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: 1,
                wheel2: 0,
                wheel3: 0
            ))
            now = Double(step) / 120
            XCTAssertNil(transformer.transform(event))
            now += 1.0 / 120.0
            smoothedTransformer.tick()
        }

        var sawVerticalMomentum = false
        for _ in 0 ..< 30 {
            now += 1.0 / 120.0
            smoothedTransformer.tick()
            if let view = emittedEvents.last.map(ScrollWheelEventView.init), abs(view.deltaYPt) > 0.01 {
                sawVerticalMomentum = true
            }
        }
        XCTAssertTrue(sawVerticalMomentum)

        let shiftedEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        shiftedEvent.flags = [.maskShift]
        XCTAssertNil(transformer.transform(shiftedEvent))

        now += 1.0 / 120.0
        smoothedTransformer.tick()

        let switchedView = try ScrollWheelEventView(XCTUnwrap(emittedEvents.last))
        XCTAssertGreaterThan(abs(switchedView.deltaXPt), 0.01)
        XCTAssertEqual(switchedView.deltaYPt, 0, accuracy: 0.001)
    }

    func testSmoothedScrollingPreservesUnsmoothedAxisAndEmitsSyntheticEvent() throws {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(
                vertical: .init(
                    enabled: true,
                    preset: .smooth,
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
                vertical: Scheme.Scrolling.Smoothed.Preset.smooth.defaultConfiguration
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
        XCTAssertEqual(transformedView.deltaYPt, 0, accuracy: 0.001)
        XCTAssertGreaterThan(transformedView.deltaYFixedPt, 0)
        XCTAssertLessThan(transformedView.deltaYFixedPt, 9)
        XCTAssertEqual(transformedView.scrollPhase, .began)
    }

    func testExtendedSpeedRangeProducesMuchStrongerInitialEmission() throws {
        let baseline = try firstDiscreteEmission(
            configuration: .init(
                enabled: true,
                preset: .easeInOut,
                response: Decimal(string: "0.68"),
                speed: Decimal(string: "3.0"),
                acceleration: Decimal(string: "1.10"),
                inertia: Decimal(string: "0.74")
            )
        )
        let boosted = try firstDiscreteEmission(
            configuration: .init(
                enabled: true,
                preset: .easeInOut,
                response: Decimal(string: "0.68"),
                speed: Decimal(string: "8.0"),
                acceleration: Decimal(string: "1.10"),
                inertia: Decimal(string: "0.74")
            )
        )

        XCTAssertGreaterThan(abs(boosted.deltaYPt), abs(baseline.deltaYPt) * 1.8)
    }

    func testExtendedResponseRangeProducesMuchQuickerPickup() throws {
        let baseline = try firstDiscreteEmission(
            configuration: .init(
                enabled: true,
                preset: .easeInOut,
                response: Decimal(string: "1.0"),
                speed: Decimal(string: "1.00"),
                acceleration: Decimal(string: "1.10"),
                inertia: Decimal(string: "0.74")
            )
        )
        let extended = try firstDiscreteEmission(
            configuration: .init(
                enabled: true,
                preset: .easeInOut,
                response: Decimal(string: "2.0"),
                speed: Decimal(string: "1.00"),
                acceleration: Decimal(string: "1.10"),
                inertia: Decimal(string: "0.74")
            )
        )

        XCTAssertGreaterThan(abs(extended.deltaYPt), abs(baseline.deltaYPt) * 1.25)
    }

    private func firstDiscreteEmission(
        configuration: Scheme.Scrolling.Smoothed
    ) throws -> ScrollWheelEventView {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: configuration),
            now: { now },
            eventSink: { emittedEvents.append($0.copy() ?? $0) }
        )

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))

        XCTAssertNil(transformer.transform(event))

        now = 1.0 / 120.0
        transformer.tick()

        return try ScrollWheelEventView(XCTUnwrap(emittedEvents.first))
    }
}
