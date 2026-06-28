// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
@testable import GestureKit
@testable import LinearMouse
import XCTest

private let gestureHIDTypeField = CGEventField(rawValue: 110)!
private let gestureStartEndSeriesTypeField = CGEventField(rawValue: 117)!
private let gesturePhaseField = CGEventField(rawValue: 132)!

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

        let transformedEvent = try XCTUnwrap(transformer.transform(
            originalEvent,
            in: EventTransformerContext(device: nil)
        ))
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

        XCTAssertNil(baselineChain.transform(baselineEvent, in: EventTransformerContext(device: nil)))
        XCTAssertNil(scaledChain.transform(scaledEvent, in: EventTransformerContext(device: nil)))

        now = 1.0 / 120.0
        baselineTransformer.tick()
        scaledTransformer.tick()

        let baselineView = try ScrollWheelEventView(XCTUnwrap(baselineEmittedEvents.firstScrollWheelEvent))
        let scaledView = try ScrollWheelEventView(XCTUnwrap(scaledEmittedEvents.firstScrollWheelEvent))
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
            XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
            now += 1.0 / 120.0
            smoothedTransformer.tick()
        }

        var sawVerticalMomentum = false
        for _ in 0 ..< 30 {
            now += 1.0 / 120.0
            smoothedTransformer.tick()
            if let view = emittedEvents.lastScrollWheelEvent.map(ScrollWheelEventView.init), abs(view.deltaYPt) > 0.01 {
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
        XCTAssertNil(transformer.transform(shiftedEvent, in: EventTransformerContext(device: nil)))

        now += 1.0 / 120.0
        smoothedTransformer.tick()

        let switchedView = try ScrollWheelEventView(XCTUnwrap(emittedEvents.lastScrollWheelEvent))
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

        let passthroughEvent = try XCTUnwrap(transformer.transform(
            originalEvent,
            in: EventTransformerContext(device: nil)
        ))
        let passthroughView = ScrollWheelEventView(passthroughEvent)
        XCTAssertEqual(passthroughView.deltaX, 3)
        XCTAssertEqual(passthroughView.deltaY, 0)

        now = 1.0 / 120.0
        transformer.tick()

        let emittedEvent = try XCTUnwrap(emittedEvents.firstScrollWheelEvent)
        let emittedView = ScrollWheelEventView(emittedEvent)
        XCTAssertTrue(emittedEvent.isLinearMouseSyntheticEvent)
        XCTAssertEqual(emittedView.deltaX, 0)
        XCTAssertEqual(emittedView.scrollPhase, .began)
        XCTAssertEqual(emittedView.momentumPhase, .none)
        XCTAssertGreaterThan(abs(emittedView.deltaYPt), 0)
        XCTAssertEqual(emittedEvent.flags, [.maskAlternate])

        let gestureEventType = try XCTUnwrap(CGEventType(nsEventType: .gesture))
        let gestureEvents = emittedEvents.filter { $0.type == gestureEventType }
        XCTAssertEqual(gestureEvents.count, 3)
        XCTAssertEqual(gestureEvents[0].getIntegerValueField(gestureHIDTypeField), 6)
        XCTAssertEqual(
            gestureEvents[0].getIntegerValueField(gesturePhaseField),
            Int64(CGSGesturePhase.mayBegin.rawValue)
        )
        XCTAssertEqual(gestureEvents[1].getIntegerValueField(gestureHIDTypeField), 61)
        XCTAssertEqual(
            gestureEvents[1].getIntegerValueField(gestureStartEndSeriesTypeField),
            6
        )
        XCTAssertEqual(gestureEvents[2].getIntegerValueField(gestureHIDTypeField), 6)
        XCTAssertEqual(
            gestureEvents[2].getIntegerValueField(gesturePhaseField),
            Int64(CGSGesturePhase.began.rawValue)
        )
        XCTAssertTrue(gestureEvents[2].flags.contains(.maskAlternate))
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

        XCTAssertNil(transformer.transform(originalEvent, in: EventTransformerContext(device: nil)))

        now = 1.0 / 120.0
        transformer.tick()

        let emittedEvent = try XCTUnwrap(emittedEvents.firstScrollWheelEvent)
        let emittedView = ScrollWheelEventView(emittedEvent)
        XCTAssertGreaterThan(abs(emittedView.deltaYPt), 3)
        XCTAssertEqual(emittedView.scrollPhase, .began)
    }

    func testContinuousTrackpadInputWithNativePhaseIsSmoothedInPlace() throws {
        let now = 0.0
        let currentTime: () -> TimeInterval = { now }
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(
                vertical: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration
            ),
            now: currentTime
        )

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

        let transformedEvent = try XCTUnwrap(transformer.transform(
            originalEvent,
            in: EventTransformerContext(device: nil)
        ))
        let transformedView = ScrollWheelEventView(transformedEvent)
        XCTAssertEqual(transformedView.deltaYPt, 0, accuracy: 0.001)
        XCTAssertGreaterThan(transformedView.deltaYFixedPt, 0)
        XCTAssertLessThan(transformedView.deltaYFixedPt, 9)
        XCTAssertEqual(transformedView.scrollPhase, .began)
    }

    func testDiscreteSmoothedScrollingCanSuppressBouncingPhases() throws {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        var configuration = Scheme.Scrolling.Smoothed.Preset.smooth.defaultConfiguration
        configuration.bouncing = false
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: configuration),
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

        XCTAssertNil(transformer.transform(originalEvent, in: EventTransformerContext(device: nil)))

        now = 1.0 / 120.0
        transformer.tick()

        let emittedEvent = try XCTUnwrap(emittedEvents.firstScrollWheelEvent)
        let emittedView = ScrollWheelEventView(emittedEvent)
        XCTAssertTrue(emittedEvent.isLinearMouseSyntheticEvent)
        XCTAssertGreaterThan(abs(emittedView.deltaYPt), 0)
        XCTAssertNil(emittedView.scrollPhase)
        XCTAssertEqual(emittedView.momentumPhase, .none)
        let gestureEventType = try XCTUnwrap(CGEventType(nsEventType: .gesture))
        XCTAssertFalse(emittedEvents.contains { $0.type == gestureEventType })
    }

    func testContinuousTrackpadInputCanSuppressBouncingPhases() throws {
        let now = 0.0
        let currentTime: () -> TimeInterval = { now }
        var configuration = Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration
        configuration.bouncing = false
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: configuration),
            now: currentTime
        )

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

        let transformedEvent = try XCTUnwrap(transformer.transform(
            originalEvent,
            in: EventTransformerContext(device: nil)
        ))
        let transformedView = ScrollWheelEventView(transformedEvent)
        XCTAssertGreaterThan(transformedView.deltaYFixedPt, 0)
        XCTAssertLessThan(transformedView.deltaYFixedPt, 9)
        XCTAssertNil(transformedView.scrollPhase)
        XCTAssertEqual(transformedView.momentumPhase, .none)
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

    func testSmoothedPointDeltaAccumulatorCarriesFractionalPixels() {
        var accumulator = SmoothedScrollPointDeltaAccumulator()

        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.4), 0)
        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.4), 0)
        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.4), 1)
        XCTAssertEqual(accumulator.verticalPointDelta(for: -0.2), 0)

        XCTAssertEqual(accumulator.horizontalPointDelta(for: -0.6), 0)
        XCTAssertEqual(accumulator.horizontalPointDelta(for: -0.6), -1)

        accumulator.reset()
        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.6), 0)
    }

    func testSmoothedPointDeltaAccumulatorCanTruncateFractionalTailPixels() {
        var accumulator = SmoothedScrollPointDeltaAccumulator()

        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.6), 0)
        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.6, accumulates: false), 0)
        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.6), 0)
        XCTAssertEqual(accumulator.verticalPointDelta(for: 1.6, accumulates: false), 1)
        XCTAssertEqual(accumulator.verticalPointDelta(for: 0.6), 0)
    }

    func testSyntheticSmoothedScrollingExposesMovementThroughScrollingDelta() throws {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: Scheme.Scrolling.Smoothed.Preset.smooth.defaultConfiguration),
            highResolutionWheelMultiplier: { _ in 8 },
            now: { now },
            eventSink: { emittedEvents.append($0.copy() ?? $0) }
        )
        let context = EventTransformerContext(device: nil)

        for step in 0 ..< 8 {
            now = Double(step) / 120.0
            let rawEvent = try makeVerticalHighResolutionScrollEvent()
            XCTAssertNil(transformer.transform(rawEvent, in: context))

            now += 1.0 / 120.0
            transformer.tick()
        }

        for _ in 0 ..< 60 {
            now += 1.0 / 120.0
            transformer.tick()
        }

        let scrollEvents = emittedEvents.filter { $0.type == .scrollWheel }
        XCTAssertFalse(scrollEvents.isEmpty)

        let movementEvents = scrollEvents.filter { event in
            let view = ScrollWheelEventView(event)
            return hasVerticalDelta(view)
        }
        XCTAssertFalse(movementEvents.isEmpty)

        for event in movementEvents {
            let view = ScrollWheelEventView(event)
            let nsEvent = try XCTUnwrap(NSEvent(cgEvent: event))
            XCTAssertNotEqual(nsEvent.scrollingDeltaY, 0)
            XCTAssertEqual(view.deltaYFixedPt, view.deltaYPt, accuracy: 0.001)
        }

        let zeroMovementEvents = scrollEvents.filter { event in
            !hasVerticalDelta(ScrollWheelEventView(event))
        }
        for event in zeroMovementEvents {
            let view = ScrollWheelEventView(event)
            XCTAssertFalse(view.scrollPhase == .began || view.scrollPhase == .changed)
            XCTAssertFalse(view.momentumPhase == .begin || view.momentumPhase == .continuous)
        }
    }

    func testSmoothedHighResolutionWheelDoesNotForceSingleRawTickToOnePixel() throws {
        var highResolutionEvents: [CGEvent] = []
        var now = 0.0
        let highResolutionTransformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration),
            highResolutionWheelMultiplier: { _ in 8 },
            now: { now },
            eventSink: { highResolutionEvents.append($0.copy() ?? $0) }
        )
        let context = EventTransformerContext(device: nil)

        XCTAssertNil(try highResolutionTransformer.transform(
            makeVerticalHighResolutionScrollEvent(),
            in: context
        ))
        for _ in 0 ..< 10 {
            now += 1.0 / 120.0
            highResolutionTransformer.tick()
        }

        XCTAssertNil(highResolutionEvents.lastScrollWheelEvent)
    }

    func testSmoothedHighResolutionWheelKeepsSlowAndFastBurstsDistinctThroughTransformer() throws {
        let slowPeak = try highResolutionTouchPeak(
            for: highResolutionRawDetentInputs(detentInterval: 0.16)
        )
        let normalPeak = try highResolutionTouchPeak(
            for: highResolutionRawDetentInputs(detentInterval: 1.0 / 55.0)
        )
        let fastPeak = try highResolutionTouchPeak(for: loggedFastHighResolutionInputs())

        XCTAssertGreaterThan(slowPeak, 0)
        XCTAssertGreaterThan(normalPeak, slowPeak * 2.0)
        XCTAssertGreaterThan(fastPeak, normalPeak)
    }

    func testSmoothedNormalHighResolutionDetentDoesNotOvershootLowResolutionDetentThroughTransformer() throws {
        let lowResolutionPeak = try lowResolutionSingleDetentTouchPeak()
        let slowHighResolutionPeak = try highResolutionTouchPeak(
            for: highResolutionRawDetentInputs(detentInterval: 0.16)
        )
        let normalHighResolutionPeak = try highResolutionTouchPeak(
            for: highResolutionRawDetentInputs(detentInterval: 1.0 / 55.0)
        )

        XCTAssertGreaterThan(lowResolutionPeak, 0)
        XCTAssertGreaterThan(slowHighResolutionPeak, lowResolutionPeak * 0.25)
        XCTAssertLessThan(slowHighResolutionPeak, lowResolutionPeak * 0.75)
        XCTAssertGreaterThan(normalHighResolutionPeak, slowHighResolutionPeak * 2.0)
        XCTAssertLessThan(normalHighResolutionPeak, lowResolutionPeak * 1.05)
    }

    func testSmoothedHighResolutionSingleDetentTotalOutputStaysCloseToLowResolutionThroughTransformer() throws {
        let lowResolutionOutput = try lowResolutionSingleDetentTotalDelta()
        let slowHighResolutionOutput = try highResolutionTotalDelta(
            for: highResolutionRawDetentInputs(detentInterval: 0.16)
        )
        let normalHighResolutionOutput = try highResolutionTotalDelta(
            for: highResolutionRawDetentInputs(detentInterval: 1.0 / 55.0)
        )

        XCTAssertGreaterThan(lowResolutionOutput, 0)
        XCTAssertGreaterThan(slowHighResolutionOutput, lowResolutionOutput * 0.25)
        XCTAssertLessThan(slowHighResolutionOutput, lowResolutionOutput * 0.75)
        XCTAssertGreaterThan(normalHighResolutionOutput, slowHighResolutionOutput * 2.0)
        XCTAssertLessThan(normalHighResolutionOutput, lowResolutionOutput * 1.25)
    }

    func testSmoothedHighResolutionWheelTotalOutputTracksInputDensityThroughTransformer() throws {
        let slowOutput = try highResolutionTotalDelta(
            for: highResolutionRawDetentInputs(detentInterval: 0.16, count: 4)
        )
        let normalOutput = try highResolutionTotalDelta(
            for: highResolutionRawDetentInputs(detentInterval: 0.08, count: 4)
        )
        let fastOutput = try highResolutionTotalDelta(
            for: highResolutionRawDetentInputs(detentInterval: 1.0 / 55.0, count: 4)
        )

        XCTAssertGreaterThan(slowOutput, 0)
        XCTAssertGreaterThan(normalOutput, slowOutput)
        XCTAssertGreaterThan(fastOutput, normalOutput)
    }

    func testSmoothedHighResolutionSingleRawTickIgnoresNativeAccelerationHint() {
        let units = SmoothedScrollingTransformer.smoothedHighResolutionUnits(
            from: .init(rawUnits: 1, acceleratedUnits: 14, units: 14)
        )

        XCTAssertEqual(units, 1, accuracy: 0.001)
    }

    func testSmoothedHighResolutionCoalescedRawTicksUseNativeAccelerationHint() {
        let units = SmoothedScrollingTransformer.smoothedHighResolutionUnits(
            from: .init(rawUnits: 4, acceleratedUnits: 14, units: 14)
        )

        XCTAssertEqual(units, 11.5, accuracy: 0.001)
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

        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))

        now = 1.0 / 120.0
        transformer.tick()

        return try ScrollWheelEventView(XCTUnwrap(emittedEvents.firstScrollWheelEvent))
    }

    private func hasVerticalDelta(_ view: ScrollWheelEventView) -> Bool {
        view.deltaY != 0 ||
            view.deltaYPt != 0 ||
            view.deltaYFixedPt != 0 ||
            view.ioHidScrollY != 0
    }

    private func makeVerticalHighResolutionScrollEvent(
        multiplier: Int = 8,
        units: Double = 1
    ) throws -> CGEvent {
        try makeVerticalHighResolutionScrollEvent(
            integerDelta: Int64(units.sign == .minus ? -1 : 1),
            fixedPointDelta: units / Double(multiplier),
            pointDelta: units * 10 / Double(multiplier),
            ioHidDelta: units.sign == .minus ? -1 : 1
        )
    }

    private struct TimedHighResolutionScrollInput {
        var timestamp: TimeInterval
        var integerDelta: Int64
        var fixedPointDelta: Double
        var pointDelta: Double
        var ioHidDelta: Double
    }

    private func highResolutionTouchPeak(
        for inputs: [TimedHighResolutionScrollInput]
    ) throws -> Double {
        try touchPeak(in: highResolutionEvents(for: inputs))
    }

    private func highResolutionTotalDelta(
        for inputs: [TimedHighResolutionScrollInput]
    ) throws -> Double {
        try totalDelta(in: highResolutionEvents(for: inputs))
    }

    private func highResolutionEvents(
        for inputs: [TimedHighResolutionScrollInput]
    ) throws -> [CGEvent] {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration),
            highResolutionWheelMultiplier: { _ in 8 },
            now: { now },
            eventSink: { emittedEvents.append($0.copy() ?? $0) }
        )
        let context = EventTransformerContext(device: nil)
        let sortedInputs = inputs.sorted { $0.timestamp < $1.timestamp }
        let tickInterval = 1.0 / 120.0
        let finalTimestamp = (sortedInputs.last?.timestamp ?? 0) + 0.5
        let tickCount = Int((finalTimestamp / tickInterval).rounded(.up))
        var nextInputIndex = 0

        for tick in 1 ... tickCount {
            let timestamp = Double(tick) * tickInterval

            while nextInputIndex < sortedInputs.count,
                  sortedInputs[nextInputIndex].timestamp <= timestamp {
                let input = sortedInputs[nextInputIndex]
                now = input.timestamp
                let event = try makeVerticalHighResolutionScrollEvent(
                    integerDelta: input.integerDelta,
                    fixedPointDelta: input.fixedPointDelta,
                    pointDelta: input.pointDelta,
                    ioHidDelta: input.ioHidDelta
                )
                XCTAssertNil(transformer.transform(event, in: context))
                nextInputIndex += 1
            }

            now = timestamp
            transformer.tick()
        }

        return emittedEvents
    }

    private func lowResolutionSingleDetentTouchPeak() throws -> Double {
        try touchPeak(in: lowResolutionSingleDetentEvents())
    }

    private func lowResolutionSingleDetentTotalDelta() throws -> Double {
        try totalDelta(in: lowResolutionSingleDetentEvents())
    }

    private func lowResolutionSingleDetentEvents() throws -> [CGEvent] {
        var emittedEvents: [CGEvent] = []
        var now = 0.0
        let transformer = SmoothedScrollingTransformer(
            smoothed: .init(vertical: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration),
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

        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
        for tick in 1 ... 60 {
            now = Double(tick) / 120.0
            transformer.tick()
        }

        return emittedEvents
    }

    private func touchPeak(in emittedEvents: [CGEvent]) -> Double {
        let scrollEvents = emittedEvents.filter { $0.type == .scrollWheel }
        let scrollViews = scrollEvents.map(ScrollWheelEventView.init)
        let touchViews = scrollViews.filter { view in
            view.scrollPhase == .began || view.scrollPhase == .changed
        }
        let touchDeltas = touchViews.map { abs($0.deltaYPt) }

        return touchDeltas.max() ?? 0
    }

    private func totalDelta(in emittedEvents: [CGEvent]) -> Double {
        emittedEvents
            .filter { $0.type == .scrollWheel }
            .map { abs(ScrollWheelEventView($0).deltaYPt) }
            .reduce(0, +)
    }

    private func slowHighResolutionRawTickInputs(
        count: Int,
        interval: TimeInterval
    ) -> [TimedHighResolutionScrollInput] {
        (0 ..< count).map { index in
            TimedHighResolutionScrollInput(
                timestamp: Double(index) * interval,
                integerDelta: 1,
                fixedPointDelta: 0.100006103515625,
                pointDelta: 1,
                ioHidDelta: 1
            )
        }
    }

    private func highResolutionRawDetentInputs(
        detentInterval: TimeInterval,
        count: Int = 1,
        multiplier: Int = 8
    ) -> [TimedHighResolutionScrollInput] {
        let unitInterval = detentInterval / Double(multiplier)
        let fixedPointDelta = 1.0 / Double(multiplier)
        let pointDelta = 10.0 / Double(multiplier)

        return (0 ..< count * multiplier).map { index in
            TimedHighResolutionScrollInput(
                timestamp: Double(index) * unitInterval,
                integerDelta: 1,
                fixedPointDelta: fixedPointDelta,
                pointDelta: pointDelta,
                ioHidDelta: 1
            )
        }
    }

    private func loggedFastHighResolutionInputs() -> [TimedHighResolutionScrollInput] {
        let timestamps = [
            899_937_042_327,
            899_937_940_863,
            899_939_561_641,
            899_940_281_411,
            899_940_480_800,
            899_940_822_651,
            899_941_188_304,
            899_942_074_311
        ]
        let integerDeltas: [Int64] = [1, 1, 2, 3, 5, 6, 7, 7]
        let fixedPointDeltas = [
            0.100006103515625,
            0.790863037109375,
            2.229400634765625,
            3.87945556640625,
            5.57720947265625,
            6.332366943359375,
            7.0001983642578125,
            7.4188232421875
        ]
        let pointDeltas = [1.0, 8, 23, 39, 56, 64, 71, 75]
        let startTimestamp = timestamps[0]

        return timestamps.indices.map { index in
            TimedHighResolutionScrollInput(
                timestamp: Double(timestamps[index] - startTimestamp) / 1_000_000_000.0,
                integerDelta: integerDeltas[index],
                fixedPointDelta: fixedPointDeltas[index],
                pointDelta: pointDeltas[index],
                ioHidDelta: 1
            )
        }
    }

    private func makeVerticalHighResolutionScrollEvent(
        integerDelta: Int64,
        fixedPointDelta: Double,
        pointDelta: Double,
        ioHidDelta: Double
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(integerDelta),
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.deltaYFixedPt = fixedPointDelta
        view.deltaYPt = pointDelta
        view.ioHidScrollY = ioHidDelta
        return event
    }
}

private extension [CGEvent] {
    var firstScrollWheelEvent: CGEvent? {
        first { $0.type == .scrollWheel }
    }

    var lastScrollWheelEvent: CGEvent? {
        last { $0.type == .scrollWheel }
    }
}
