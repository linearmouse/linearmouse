// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ScrollMomentumMappingTests: XCTestCase {
    func testTailRetainsMappingAndFractionalDistanceAcrossRouteAndModifierChanges() throws {
        let ownership = ScrollGestureOwnership()
        let recognizer = ScrollActionRecognizer(gesture: ownership)
        let input = ScrollInput(axis: .vertical, delta: 4, units: .points, hasPhase: true)
        let action = Scheme.Buttons.Mapping.Action.arg1(.mouseWheelScrollRight(.pixel(8)))
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: true, at: 0), 0)
        var output: [Scheme.Buttons.Mapping.Action] = []
        recognizer.retainScrollMomentum(
            input: input, mapping: 0, action: action, highResolutionMultiplier: nil, clock: { 1 }
        ) { output.append($0) }
        recognizer.endGesture()
        recognizer.discardMovement()
        recognizer.updateModifiers(1)
        recognizer.updateModifiers(0)
        let nextRoute = ScrollGestureTransformer(ownership: ownership)
        // Same original axis but a different sign after a route reversal: the
        // pinned output remains rightward, and the initial 4 points are retained.
        let tail = try momentum(delta: -4, phase: .begin)
        XCTAssertNil(nextRoute.transform(tail, in: .init(device: nil)))
        XCTAssertEqual(output, [action])
        let end = try momentum(delta: -16, phase: .end)
        XCTAssertNil(nextRoute.transform(end, in: .init(device: nil)))
        XCTAssertEqual(output, [action, .arg1(.mouseWheelScrollRight(.pixel(16)))])
        XCTAssertFalse(ownership.isOwned)
        XCTAssertNotNil(nextRoute.transform(tail, in: .init(device: nil)))
        XCTAssertEqual(output.count, 2)
    }

    func testMomentumEventSplittingPreservesMappedDistanceWithoutThrottle() throws {
        for pieces in [1, 2, 16] {
            let ownership = ScrollGestureOwnership()
            let recognizer = ScrollActionRecognizer(gesture: ownership)
            let input = ScrollInput(axis: .vertical, delta: 8, units: .points, hasPhase: true)
            _ = recognizer.consume(input, mapping: 0, repeats: true, at: 0)
            var distance: Decimal = 0
            recognizer.retainScrollMomentum(
                input: input,
                mapping: 0,
                action: .arg1(.mouseWheelScrollLeft(.pixel(1.5))),
                highResolutionMultiplier: nil,
                clock: { 1 }
            ) { action in
                guard case let .arg1(.mouseWheelScrollLeft(.pixel(value))) = action else {
                    return XCTFail("Unexpected mapping")
                }
                distance += value
            }
            let gate = ScrollGestureTransformer(ownership: ownership)
            for _ in 0 ..< pieces {
                XCTAssertNil(try gate.transform(
                    momentum(delta: 128 / Double(pieces), phase: .continuous),
                    in: .init(device: nil)
                ))
            }
            XCTAssertEqual(distance, 24)
        }
    }

    func testNewGestureAndDiscreteCommandDiscardPreviousContinuation() throws {
        let ownership = ScrollGestureOwnership()
        let recognizer = ScrollActionRecognizer(gesture: ownership)
        let input = ScrollInput(axis: .vertical, delta: 8, units: .points, hasPhase: true)
        let gate = ScrollGestureTransformer(ownership: ownership)
        var calls = 0
        for newGesture in [true, false] {
            _ = recognizer.consume(input, mapping: 0, repeats: true, at: 0)
            recognizer.retainScrollMomentum(
                input: input,
                mapping: 0,
                action: .arg0(.mouseWheelScrollRight),
                highResolutionMultiplier: nil,
                clock: { 1 }
            ) { _ in calls += 1 }
            if newGesture {
                let event = try momentum(delta: 8, phase: .none)
                ScrollWheelEventView(event).scrollPhase = .began
                XCTAssertNotNil(gate.transform(event, in: .init(device: nil)))
                XCTAssertNotNil(try gate.transform(momentum(delta: 16, phase: .begin), in: .init(device: nil)))
            } else {
                _ = recognizer.consume(input, mapping: 1, repeats: false, at: 1)
                XCTAssertNil(try gate.transform(momentum(delta: 16, phase: .begin), in: .init(device: nil)))
            }
        }
        XCTAssertEqual(calls, 0)
    }

    func testUnmappedDirectInputReleasesOldMappingButKeepsCooldown() throws {
        let ownership = ScrollGestureOwnership()
        let throttle = ScrollActionThrottle()
        let recognizer = ScrollActionRecognizer(throttle: throttle, gesture: ownership)
        let input = ScrollInput(axis: .vertical, delta: 4, units: .points, hasPhase: true)
        let action = Scheme.Buttons.Mapping.Action.arg1(.mouseWheelScrollRight(.pixel(8)))
        XCTAssertTrue(throttle.allowsAction(on: .vertical, at: 0))
        _ = recognizer.consume(input, mapping: 0, repeats: true, at: 0)
        var output: [Scheme.Buttons.Mapping.Action] = []
        recognizer.retainScrollMomentum(
            input: input, mapping: 0, action: action, highResolutionMultiplier: nil, clock: { 1 }
        ) { output.append($0) }
        let transformer = ButtonMappingTransformer(
            mappings: [
                .init(trigger: .init(input: .wheel(.up), modifiers: [.control]), action: action)
            ],
            scrollRecognizer: recognizer
        )
        // Control was released, and direct scrolling continues in the SAME direction.
        let direct = try momentum(delta: 8, phase: .none)
        ScrollWheelEventView(direct).scrollPhase = .changed
        let gate = ScrollGestureTransformer(ownership: ownership)
        let pipeline: [EventTransformer] = [gate, transformer]
        XCTAssertNotNil(pipeline.transform(direct, in: .init(device: nil)))
        XCTAssertFalse(ownership.isOwned)
        XCTAssertNotNil(try gate.transform(momentum(delta: 8, phase: .begin), in: .init(device: nil)))
        XCTAssertTrue(output.isEmpty)
        XCTAssertFalse(throttle.allowsAction(on: .vertical, at: 100_000_000))
    }

    func testZeroDeltaEndPreservesContinuation() throws {
        let ownership = ScrollGestureOwnership()
        let recognizer = ScrollActionRecognizer(gesture: ownership)
        let input = ScrollInput(axis: .vertical, delta: 4, units: .points, hasPhase: true)
        _ = recognizer.consume(input, mapping: 0, repeats: true, at: 0)
        var output: [Scheme.Buttons.Mapping.Action] = []
        recognizer.retainScrollMomentum(
            input: input,
            mapping: 0,
            action: .arg0(.mouseWheelScrollRight),
            highResolutionMultiplier: nil,
            clock: { 1 }
        ) { output.append($0) }
        let gate = ScrollGestureTransformer(ownership: ownership)
        let end = try momentum(delta: 0, phase: .none)
        ScrollWheelEventView(end).scrollPhase = .ended
        XCTAssertNotNil(gate.transform(end, in: .init(device: nil)))
        XCTAssertTrue(ownership.isOwned)
        XCTAssertNil(try gate.transform(momentum(delta: 4, phase: .begin), in: .init(device: nil)))
        XCTAssertEqual(output, [.arg1(.mouseWheelScrollRight(.line(3)))])
    }

    private func momentum(delta: Double, phase: CGMomentumScrollPhase) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0
        ))
        event.flags = []
        let view = ScrollWheelEventView(event)
        view.continuous = true
        view.deltaYPt = delta
        view.scrollPhase = nil
        view.momentumPhase = phase
        return event
    }
}
