// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: TESTS
//
// Overview of the feature: Documentation/Glide.md
//
// Contents
//   1. GlideCurveTests              The easing curve starts at 0, ends at 1,
//                                   lands gently and never goes backwards.
//   2. GlideScrollingAxisTests      Clicks add up to exact distances, glides
//                                   end on time, speed carries across clicks,
//                                   reversing drops the unfinished distance.
//   3. GlideScrollingTransformerTests
//                                   Wheel clicks are swallowed and replayed as
//                                   plain pixel events; trackpad input and
//                                   other axes pass through; a hidden cursor
//                                   (game) gets one click per notch.
//   4. GlideFrameTimingTests        Steps are even from frame to frame, even
//                                   when clicks arrive between frames.
//
// Tests drive time by hand (a fake clock and `tick()`), so they are
// deterministic and need no display.

import AppKit
@testable import LinearMouse
import XCTest

// MARK: - 1. Curve

final class GlideCurveTests: XCTestCase {
    func testCurveEndpointsAndLanding() {
        for slope in stride(from: 0.0, through: 4.0, by: 0.5) {
            let curve = GlideCurve(initialSlope: slope)
            XCTAssertEqual(curve.value(at: 0), 0, accuracy: 1e-12)
            XCTAssertEqual(curve.value(at: 1), 1, accuracy: 1e-12)
            XCTAssertEqual(curve.slope(at: 0), slope, accuracy: 1e-12)
            XCTAssertEqual(curve.slope(at: 1), 0, accuracy: 1e-12)
        }
    }

    func testCurveIsMonotonic() {
        for slope in stride(from: 0.0, through: 4.0, by: 0.25) {
            let curve = GlideCurve(initialSlope: slope)
            var previous = 0.0
            for step in 1 ... 200 {
                let value = curve.value(at: Double(step) / 200)
                XCTAssertGreaterThanOrEqual(value, previous - 1e-12)
                XCTAssertLessThanOrEqual(value, 1 + 1e-12)
                previous = value
            }
        }
    }

    func testEaseOutCubicMatchesClosedForm() {
        let curve = GlideCurve(initialSlope: 3)
        for step in 0 ... 10 {
            let s = Double(step) / 10
            XCTAssertEqual(curve.value(at: s), 1 - pow(1 - s, 3), accuracy: 1e-12)
        }
    }
}

// MARK: - 2. One axis

final class GlideScrollingAxisTests: XCTestCase {
    private let settings = GlideScrollingAxis.Settings(pixelsPerDetent: 30, duration: 0.18, initialSlope: 3)

    private func run(
        _ axis: inout GlideScrollingAxis,
        from start: TimeInterval,
        to end: TimeInterval,
        step: TimeInterval = 1.0 / 120.0
    ) -> [Double] {
        var deltas: [Double] = []
        var time = start
        while time <= end {
            deltas.append(axis.advance(to: time))
            time += step
        }
        return deltas
    }

    func testSingleDetentStopsExactlyOnTarget() {
        var axis = GlideScrollingAxis(settings: settings)
        axis.add(detents: 1, at: 0)
        let deltas = run(&axis, from: 0, to: 0.5)

        XCTAssertEqual(deltas.reduce(0, +), 30, accuracy: 1e-9)
        XCTAssertTrue(deltas.allSatisfy { $0 >= 0 })
        XCTAssertFalse(axis.isActive)
    }

    func testGlideEndsAfterDuration() {
        // A glide from rest starts one frame before its first sampled frame.
        var axis = GlideScrollingAxis(settings: settings)
        axis.add(detents: 1, at: 0)
        _ = axis.advance(to: 0.01, frameInterval: 0.01)
        _ = axis.advance(to: 0.1, frameInterval: 0.01)
        XCTAssertTrue(axis.isActive)
        _ = axis.advance(to: 0.18, frameInterval: 0.01)
        XCTAssertFalse(axis.isActive)
    }

    func testRepeatedDetentsExtendTargetWithoutBacktracking() {
        var axis = GlideScrollingAxis(settings: settings)
        var total = 0.0
        var time = 0.0
        for click in 0 ..< 5 {
            axis.add(detents: 1, at: Double(click) * 0.04)
            while time < Double(click + 1) * 0.04 {
                let delta = axis.advance(to: time)
                XCTAssertGreaterThanOrEqual(delta, 0)
                total += delta
                time += 1.0 / 120.0
            }
        }
        total += run(&axis, from: time, to: time + 0.5).reduce(0, +)

        XCTAssertEqual(total, 150, accuracy: 1e-9)
    }

    func testRetargetNeverJumpsTheSpeed() {
        var axis = GlideScrollingAxis(settings: settings)
        axis.add(detents: 1, at: 0)
        _ = axis.advance(to: 0)
        _ = axis.advance(to: 0.06)
        let before = axis.velocity(at: 0.06)
        axis.add(detents: 1, at: 0.065)
        let after = axis.velocity(at: 0.06)

        XCTAssertGreaterThan(before, 0)
        XCTAssertEqual(after, before, accuracy: before * 1e-6)
    }

    func testEaseInOutRetargetKeepsCurrentSpeed() {
        var axis = GlideScrollingAxis(
            settings: .init(pixelsPerDetent: 30, duration: 0.18, initialSlope: 0)
        )
        axis.add(detents: 1, at: 0)
        _ = axis.advance(to: 0)
        _ = axis.advance(to: 0.05)
        let before = axis.velocity(at: 0.05)
        // Arrives between frames; retargets from the last frame shown.
        axis.add(detents: 1, at: 0.055)
        let after = axis.velocity(at: 0.05)

        XCTAssertGreaterThan(before, 0)
        XCTAssertEqual(after, before, accuracy: 1e-6)
    }

    func testReversalDropsUnfinishedDistance() {
        var axis = GlideScrollingAxis(settings: settings)
        axis.add(detents: 2, at: 0)
        var total = run(&axis, from: 0, to: 0.05).reduce(0, +)
        let shown = total
        axis.add(detents: -1, at: 0.052)
        total += run(&axis, from: 0.0583, to: 1).reduce(0, +)

        XCTAssertEqual(total, shown - 30, accuracy: 1e-9)
    }
}

// MARK: - 3. Transformer (events in, events out)

final class GlideScrollingTransformerTests: XCTestCase {
    private func lineEvent(vertical: Int32, horizontal: Int32 = 0) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ))
    }

    func testDetentIsConsumedAndReplayedAsPlainPixelEvents() throws {
        var emitted: [CGEvent] = []
        var now = 0.0
        let transformer = GlideScrollingTransformer(
            glide: .init(vertical: .init(enabled: true, lines: 3, lineHeight: 10, duration: 180)),
            highResolutionWheelMultiplier: { _ in nil },
            now: { now },
            eventSink: { emitted.append($0.copy() ?? $0) },
            isCursorHidden: { false },
            makeFrameClock: { _ in ManualFrameClock() }
        )

        XCTAssertNil(try transformer.transform(lineEvent(vertical: 1), in: EventTransformerContext(device: nil)))

        while now < 0.5 {
            now += 1.0 / 120.0
            transformer.tick()
        }

        let views = emitted.map { ScrollWheelEventView($0) }
        XCTAssertFalse(views.isEmpty)
        XCTAssertEqual(views.reduce(0) { $0 + $1.deltaYPt }, 30)
        for view in views {
            XCTAssertTrue(view.continuous)
            XCTAssertNil(view.scrollPhase)
            XCTAssertEqual(view.momentumPhase, .none)
            XCTAssertGreaterThan(view.deltaYFixedPt, 0)
            XCTAssertGreaterThanOrEqual(view.deltaYPt, 0)
        }
    }

    func testAcceleratedLineDeltaStillCountsAsOneDetent() throws {
        var emitted: [CGEvent] = []
        var now = 0.0
        let transformer = GlideScrollingTransformer(
            glide: .init(vertical: .init(enabled: true, lines: 3, lineHeight: 10, duration: 180)),
            highResolutionWheelMultiplier: { _ in nil },
            now: { now },
            eventSink: { emitted.append($0.copy() ?? $0) },
            isCursorHidden: { false },
            makeFrameClock: { _ in ManualFrameClock() }
        )

        XCTAssertNil(try transformer.transform(lineEvent(vertical: 5), in: EventTransformerContext(device: nil)))
        while now < 0.5 {
            now += 1.0 / 120.0
            transformer.tick()
        }

        XCTAssertEqual(emitted.map { ScrollWheelEventView($0) }.reduce(0) { $0 + $1.deltaYPt }, 30)
    }

    func testUnownedAxisPassesThrough() throws {
        let transformer = GlideScrollingTransformer(
            glide: .init(vertical: .init(enabled: true)),
            highResolutionWheelMultiplier: { _ in nil },
            now: { 0 },
            eventSink: { _ in },
            isCursorHidden: { false },
            makeFrameClock: { _ in ManualFrameClock() }
        )

        let event = try XCTUnwrap(try transformer.transform(
            lineEvent(vertical: 1, horizontal: 1),
            in: EventTransformerContext(device: nil)
        ))
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaY, 0)
        XCTAssertEqual(view.deltaX, 1)
    }

    func testContinuousInputPassesThrough() throws {
        let transformer = GlideScrollingTransformer(
            glide: .init(vertical: .init(enabled: true)),
            highResolutionWheelMultiplier: { _ in nil },
            now: { 0 },
            eventSink: { _ in },
            isCursorHidden: { false },
            makeFrameClock: { _ in ManualFrameClock() }
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: 12,
            wheel2: 0,
            wheel3: 0
        ))

        XCTAssertNotNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
    }

    func testHiddenCursorSendsOneClickPerNotchInsteadOfGliding() throws {
        var emitted: [CGEvent] = []
        var now = 0.0
        let transformer = GlideScrollingTransformer(
            glide: .init(vertical: .init(enabled: true, lines: 3, lineHeight: 10, duration: 180)),
            highResolutionWheelMultiplier: { _ in nil },
            now: { now },
            eventSink: { emitted.append($0.copy() ?? $0) },
            isCursorHidden: { true },
            makeFrameClock: { _ in ManualFrameClock() }
        )

        // An accelerated wheel event (delta 4) still becomes exactly one click.
        let event = try XCTUnwrap(try transformer.transform(
            lineEvent(vertical: 4),
            in: EventTransformerContext(device: nil)
        ))
        let view = ScrollWheelEventView(event)
        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaY, 1)
        // The other distance fields describe the same single click.
        XCTAssertEqual(view.deltaYFixedPt, 1)
        XCTAssertEqual(view.deltaYPt, 10)

        while now < 0.5 {
            now += 1.0 / 120.0
            transformer.tick()
        }
        XCTAssertTrue(emitted.isEmpty)
    }

    func testGameDetectionOffKeepsGlidingWithHiddenCursor() throws {
        let transformer = GlideScrollingTransformer(
            glide: .init(vertical: .init(enabled: true, gameDetection: false)),
            highResolutionWheelMultiplier: { _ in nil },
            now: { 0 },
            eventSink: { _ in },
            isCursorHidden: { true },
            makeFrameClock: { _ in ManualFrameClock() }
        )

        XCTAssertNil(try transformer.transform(lineEvent(vertical: 1), in: EventTransformerContext(device: nil)))
    }

    func testCursorIsCheckedOnlyForWheelEventsGlideHandles() throws {
        var checks = 0
        let transformer = GlideScrollingTransformer(
            glide: .init(vertical: .init(enabled: true)),
            highResolutionWheelMultiplier: { _ in nil },
            now: { 0 },
            eventSink: { _ in },
            isCursorHidden: {
                checks += 1
                return false
            },
            makeFrameClock: { _ in ManualFrameClock() }
        )

        let pixelEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: 12,
            wheel2: 0,
            wheel3: 0
        ))
        _ = transformer.transform(pixelEvent, in: EventTransformerContext(device: nil))
        XCTAssertEqual(checks, 0)

        _ = try transformer.transform(lineEvent(vertical: 1), in: EventTransformerContext(device: nil))
        XCTAssertEqual(checks, 1)
    }
}

/// A frame clock that does nothing; tests call `tick()` themselves.
private final class ManualFrameClock: GlideFrameClocking {
    var frameInterval: TimeInterval {
        1.0 / 120.0
    }

    func start() {}
    func stop() {}
}

// MARK: - 4. Frame timing

final class GlideFrameTimingTests: XCTestCase {
    func testEvenFramesGiveEvenSteps() {
        // At a steady 120 Hz frame rate each step follows the curve exactly,
        // so consecutive steps never jump up (ease-out only slows down).
        var axis = GlideScrollingAxis(settings: .init(pixelsPerDetent: 30, duration: 0.18, initialSlope: 3))
        axis.add(detents: 1, at: 0)
        var previous = Double.infinity
        for frame in 1 ... 30 {
            let step = axis.advance(to: Double(frame) / 120)
            XCTAssertLessThanOrEqual(step, previous + 1e-9)
            previous = step
        }
    }

    func testDetentBetweenFramesNeverStepsBackwards() {
        var axis = GlideScrollingAxis(settings: .init(pixelsPerDetent: 30, duration: 0.18, initialSlope: 3))
        axis.add(detents: 1, at: 0)
        // Frames are sampled at display time, a little ahead of the clock.
        _ = axis.advance(to: 0.050)
        axis.add(detents: 1, at: 0.040)
        for frame in 0 ... 40 {
            XCTAssertGreaterThanOrEqual(axis.advance(to: 0.058 + Double(frame) / 120), 0)
        }
    }

    func testEveryFrameGetsAFullStepAcrossDetents() {
        // Detents between frames retarget on the frame grid, so steps stay
        // even: no short step right after a detent, then a catch-up.
        var axis = GlideScrollingAxis(settings: .init(pixelsPerDetent: 120, duration: 0.18, initialSlope: 3))
        let frame = 1.0 / 60.0
        axis.add(detents: 1, at: 0.003)
        var steps: [Double] = []
        for index in 1 ... 6 {
            if index == 3 {
                axis.add(detents: 1, at: Double(index - 1) * frame + 0.011)
            }
            steps.append(axis.advance(to: Double(index) * frame, frameInterval: frame))
        }
        // Steps change gradually across the detent: no short step followed
        // by a catch-up, and no sudden jump.
        XCTAssertTrue(steps.allSatisfy { $0 > 0 })
        for index in 1 ..< steps.count {
            XCTAssertLessThan(abs(steps[index] - steps[index - 1]), 0.35 * steps[index - 1])
        }
    }
}

final class GlideConfigurationTests: XCTestCase {
    func testRestoreDefaultsTurnsGameDetectionOn() throws {
        // Set explicitly (not left to inherit), and on.
        let gameDetection = try XCTUnwrap(Scheme.Scrolling.Glide.defaultConfiguration.gameDetection)
        XCTAssertTrue(gameDetection)
    }

    func testDistancePerClickIsAtLeastOnePixel() {
        XCTAssertEqual(Scheme.Scrolling.Glide(lines: 0.1, lineHeight: 1).pixelsPerDetent, 1)
        XCTAssertEqual(Scheme.Scrolling.Glide(lines: 0, lineHeight: 10).pixelsPerDetent, 0)
        XCTAssertEqual(Scheme.Scrolling.Glide(lines: 3, lineHeight: 10).pixelsPerDetent, 30)
    }
}
