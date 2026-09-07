// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

private final class FakeMagicMouseTouchProvider: MagicMouseTouchProviding {
    var isAvailable: Bool
    var fingerCount: Int

    init(isAvailable: Bool = true, fingerCount: Int = 0) {
        self.isAvailable = isAvailable
        self.fingerCount = fingerCount
    }
}

final class RequireTwoFingerScrollTransformerTests: XCTestCase {
    private func makeScrollEvent(momentumPhase: CGMomentumScrollPhase = .none) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        ScrollWheelEventView(event).momentumPhase = momentumPhase
        return event
    }

    private func transform(
        _ transformer: RequireTwoFingerScrollTransformer,
        momentumPhase: CGMomentumScrollPhase = .none
    ) throws -> CGEvent? {
        let event = try makeScrollEvent(momentumPhase: momentumPhase)
        return transformer.transform(event, in: EventTransformerContext(device: nil))
    }

    func testSuppressesOneFingerScroll() throws {
        let touch = FakeMagicMouseTouchProvider(fingerCount: 1)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { 0 }

        XCTAssertNil(try transform(transformer))
    }

    func testSuppressesZeroFingerScroll() throws {
        let touch = FakeMagicMouseTouchProvider(fingerCount: 0)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { 0 }

        XCTAssertNil(try transform(transformer))
    }

    func testPassesTwoFingerScroll() throws {
        let touch = FakeMagicMouseTouchProvider(fingerCount: 2)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { 0 }

        XCTAssertNotNil(try transform(transformer))
    }

    func testFailsOpenWhenTouchTrackerUnavailable() throws {
        let touch = FakeMagicMouseTouchProvider(isAvailable: false, fingerCount: 0)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { 0 }

        // No trustworthy finger-count signal - never block scrolling.
        XCTAssertNotNil(try transform(transformer))
    }

    func testIgnoresSyntheticEvents() throws {
        let touch = FakeMagicMouseTouchProvider(fingerCount: 0)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { 0 }

        let event = try makeScrollEvent()
        event.isLinearMouseSyntheticEvent = true

        XCTAssertNotNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
    }

    /// The core regression this transformer exists to fix: the Magic Mouse
    /// tags most actively-touched scroll ticks (not just the true post-lift
    /// glide) with a nonzero momentum phase. Gating must never trust that
    /// field on its own - a fresh one-finger gesture must be suppressed
    /// immediately, even if the device happens to report a nonzero momentum
    /// phase for it.
    func testDoesNotTrustMomentumPhaseForAFreshUnqualifiedGesture() throws {
        let touch = FakeMagicMouseTouchProvider(fingerCount: 1)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { 0 }

        XCTAssertNil(try transform(transformer, momentumPhase: .continuous))
    }

    func testLetsQualifiedGestureGlideAfterFingersLift() throws {
        var time: CFTimeInterval = 0
        let touch = FakeMagicMouseTouchProvider(fingerCount: 2)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { time }

        // Gesture starts and is qualified with two fingers.
        XCTAssertNotNil(try transform(transformer))

        // Fingers lift, but the gesture that already qualified keeps
        // gliding - even though a fresh one-finger touch would be blocked.
        touch.fingerCount = 0
        time += 0.05
        XCTAssertNotNil(try transform(transformer, momentumPhase: .continuous))

        time += 0.05
        XCTAssertNotNil(try transform(transformer, momentumPhase: .continuous))
    }

    func testExplicitMomentumEndClosesOutTheGlide() throws {
        var time: CFTimeInterval = 0
        let touch = FakeMagicMouseTouchProvider(fingerCount: 2)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { time }

        XCTAssertNotNil(try transform(transformer))

        touch.fingerCount = 0
        time += 0.05
        XCTAssertNotNil(try transform(transformer, momentumPhase: .end))

        // The glide has been explicitly closed out. A further tick with no
        // qualifying fingers must be blocked again, even with no time gap.
        time += 0.01
        XCTAssertNil(try transform(transformer, momentumPhase: .continuous))
    }

    func testAGapBetweenTicksEndsTheGlideEvenWithoutAnExplicitEnd() throws {
        var time: CFTimeInterval = 0
        let touch = FakeMagicMouseTouchProvider(fingerCount: 2)
        let transformer = RequireTwoFingerScrollTransformer(touchTracker: touch) { time }

        XCTAssertNotNil(try transform(transformer))

        touch.fingerCount = 0
        time += 0.05
        XCTAssertNotNil(try transform(transformer, momentumPhase: .continuous))

        // A long pause with no more ticks - the device never sent an
        // explicit `.end`. The next tick must be treated as a fresh,
        // unqualified gesture.
        time += 1.0
        XCTAssertNil(try transform(transformer, momentumPhase: .continuous))
    }
}
