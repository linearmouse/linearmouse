// MIT License
// Copyright (c) 2021-2026 LinearMouse

import GestureKit
@testable import LinearMouse
import XCTest

final class SpaceSwipeTransformerTests: XCTestCase {
    private var time: TimeInterval = 0
    private var outputs: [SpaceSwipeSession.Output] = []
    private var recording = false
    private var session: SpaceSwipeSession!

    override func setUp() {
        super.setUp()
        time = 0
        outputs = []
        recording = false
        session = makeSession()
    }

    private static let noTimers: SpaceSwipeSession.Scheduler = { _, _, _ in nil }

    private func makeSession(schedule: @escaping SpaceSwipeSession.Scheduler = noTimers) -> SpaceSwipeSession {
        SpaceSwipeSession(now: { [weak self] in self?.time ?? 0 }, schedule: schedule) { [weak self] in
            self?.outputs.append($0)
        }
    }

    private func makeTransformer(distance: Double = 10, releaseDelay: TimeInterval = 0.2) -> SpaceSwipeTransformer {
        SpaceSwipeTransformer(distance: distance, releaseDelay: releaseDelay, session: session) { [weak self] in
            self?.recording ?? false
        }
    }

    private func scrollEvent(horizontal: Int32 = 0, vertical: Int32 = 0) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ))
    }

    /// Advances the clock in animation frames, running the follow animation.
    private func runFrames(_: SpaceSwipeTransformer? = nil, for duration: TimeInterval) {
        let frame = 1.0 / 120
        var elapsed = 0.0
        while elapsed < duration {
            time += frame
            elapsed += frame
            session.frame()
        }
    }

    private var phases: [CGSGesturePhase] {
        outputs.map(\.phase)
    }

    func testVerticalScrollingPassesThrough() throws {
        let transformer = makeTransformer()
        let event = try scrollEvent(vertical: 3)

        XCTAssertNotNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
        runFrames(transformer, for: 0.5)
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertFalse(session.isActive)
    }

    func testHorizontalScrollingIsConsumedAndEasesTowardTarget() throws {
        let transformer = makeTransformer(distance: 10, releaseDelay: 1)

        XCTAssertNil(try transformer.transform(scrollEvent(horizontal: 3), in: EventTransformerContext(device: nil)))
        XCTAssertTrue(session.isActive)

        runFrames(transformer, for: 0.3)
        XCTAssertEqual(phases.first, .began)
        XCTAssertTrue(phases.dropFirst().allSatisfy { $0 == .changed })
        XCTAssertGreaterThan(outputs.count, 3, "a wheel step should spread over several frames")

        // Positive horizontal deltas mean "left", which is negative progress for the Dock.
        let progress = outputs.map(\.progress)
        XCTAssertTrue(progress.allSatisfy { $0 < 0 })
        XCTAssertEqual(progress, progress.sorted(by: >), "progress should move monotonically")
        XCTAssertEqual(try XCTUnwrap(progress.last), -0.3, accuracy: 0.01)
    }

    func testReleasesAfterWheelIsIdle() throws {
        let transformer = makeTransformer(distance: 10, releaseDelay: 0.2)

        _ = try transformer.transform(scrollEvent(horizontal: 6), in: EventTransformerContext(device: nil))
        runFrames(transformer, for: 0.15)
        XCTAssertFalse(phases.contains(.ended), "must not release before the delay")

        runFrames(transformer, for: 0.2)
        let last = try XCTUnwrap(outputs.last)
        XCTAssertEqual(last.phase, .ended)
        XCTAssertEqual(last.progress, -0.6, accuracy: 0.001)
        XCTAssertFalse(session.isActive)
    }

    func testCancelingAfterReleaseDropsPendingEndEventResends() throws {
        // Records one-shot timers so the test can fire the ones still valid.
        var oneShots: [(timer: EventThreadTimer, handler: () -> Void)] = []
        let idleThread = EventThread()
        session = makeSession { _, repeats, handler in
            let timer = EventThreadTimer(
                timer: Timer(timeInterval: 1, repeats: false) { _ in },
                eventThread: idleThread
            )
            if !repeats {
                oneShots.append((timer, handler))
            }
            return timer
        }
        let transformer = makeTransformer()

        _ = try transformer.transform(scrollEvent(horizontal: 3), in: EventTransformerContext(device: nil))
        runFrames(transformer, for: 0.5)
        XCTAssertEqual(phases.last, .ended)
        XCTAssertFalse(oneShots.isEmpty, "a release schedules end event resends")

        session.cancel()
        let endedBefore = phases.filter { $0 == .ended }.count
        for oneShot in oneShots where oneShot.timer.isValid {
            oneShot.handler()
        }
        XCTAssertEqual(phases.filter { $0 == .ended }.count, endedBefore)
    }

    func testFurtherInputKeepsTheSwipeAlive() throws {
        let transformer = makeTransformer(distance: 10, releaseDelay: 0.2)

        for _ in 0 ..< 3 {
            _ = try transformer.transform(scrollEvent(horizontal: 1), in: EventTransformerContext(device: nil))
            runFrames(transformer, for: 0.15)
        }

        XCTAssertEqual(phases.filter { $0 == .began }.count, 1)
        XCTAssertFalse(phases.contains(.ended))
        XCTAssertEqual(try XCTUnwrap(outputs.last).progress, -0.3, accuracy: 0.01)
    }

    func testTurningBackPastHalfwayStillEndsTheSwipe() throws {
        let transformer = makeTransformer(distance: 10, releaseDelay: 0.2)

        _ = try transformer.transform(scrollEvent(horizontal: 8), in: EventTransformerContext(device: nil))
        runFrames(transformer, for: 0.1)
        _ = try transformer.transform(scrollEvent(horizontal: -2), in: EventTransformerContext(device: nil))
        runFrames(transformer, for: 0.5)

        // The Dock decides by position, so a release past halfway switches spaces.
        XCTAssertFalse(phases.contains(.cancelled))
        let last = try XCTUnwrap(outputs.last)
        XCTAssertEqual(last.phase, .ended)
        XCTAssertEqual(last.progress, -0.6, accuracy: 0.001)
        XCTAssertEqual(last.velocity, 0, "a settled release carries no fling")
    }

    func testLongSpinChainsIntoTheNextSpace() throws {
        let transformer = makeTransformer(distance: 10)

        _ = try transformer.transform(scrollEvent(horizontal: 15), in: EventTransformerContext(device: nil))
        runFrames(transformer, for: 1)

        let ended = outputs.filter { $0.phase == .ended }
        XCTAssertEqual(ended.count, 2)
        XCTAssertEqual(ended[0].progress, -1, accuracy: 0.001)
        XCTAssertEqual(ended[1].progress, -0.5, accuracy: 0.01)
        XCTAssertEqual(phases.filter { $0 == .began }.count, 2)
    }

    func testTrackpadScrollingPassesThrough() throws {
        let transformer = makeTransformer()
        let event = try scrollEvent(horizontal: 3)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.began.rawValue))

        XCTAssertNotNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
        runFrames(transformer, for: 0.5)
        XCTAssertTrue(outputs.isEmpty)
    }

    func testRecordingPassesHorizontalScrollingThrough() throws {
        let transformer = makeTransformer()
        recording = true

        XCTAssertNotNil(try transformer.transform(scrollEvent(horizontal: 3), in: EventTransformerContext(device: nil)))
        runFrames(transformer, for: 0.5)
        XCTAssertTrue(outputs.isEmpty)
        XCTAssertFalse(session.isActive)
    }

    func testRecordingLetsAnActiveSwipeFinish() throws {
        let transformer = makeTransformer(distance: 10, releaseDelay: 0.2)

        _ = try transformer.transform(scrollEvent(horizontal: 3), in: EventTransformerContext(device: nil))
        runFrames(transformer, for: 0.05)
        recording = true

        XCTAssertNotNil(
            try transformer.transform(scrollEvent(horizontal: 1), in: EventTransformerContext(device: nil)),
            "recording receives the wheel even while a swipe finishes"
        )
        runFrames(transformer, for: 0.5)
        XCTAssertEqual(phases.last, .ended)
        XCTAssertEqual(try XCTUnwrap(outputs.last).progress, -0.3, accuracy: 0.001)
        XCTAssertFalse(session.isActive)

        XCTAssertNotNil(try transformer.transform(scrollEvent(horizontal: 3), in: EventTransformerContext(device: nil)))
    }

    func testSyntheticScrollingPassesThrough() throws {
        let transformer = makeTransformer()
        let event = try scrollEvent(horizontal: 3)
        event.isLinearMouseSyntheticEvent = true

        XCTAssertNotNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
        XCTAssertTrue(outputs.isEmpty)
    }

    func testCancelAbandonsActiveSwipe() throws {
        let transformer = makeTransformer()

        _ = try transformer.transform(scrollEvent(horizontal: 3), in: EventTransformerContext(device: nil))
        runFrames(transformer, for: 0.05)
        session.cancel()

        XCTAssertEqual(phases.last, .cancelled)
        XCTAssertFalse(session.isActive)
    }

    func testTransformerClaimsNoRouteInteraction() {
        // The session releases itself on a timer, so routes never pin mouse
        // buttons to a swipe or strip the transformer while a button is held.
        let transformer = makeTransformer()
        XCTAssertFalse(transformer is EventTransformerInteractionTracking)
        XCTAssertFalse(transformer is Deactivatable)
    }

    func testRoutesSharingASessionContinueOneSwipe() throws {
        // A swipe changes the app under the pointer, so the next wheel step can
        // arrive through another route with its own scheme settings.
        let firstRoute = makeTransformer(distance: 10, releaseDelay: 0.2)
        let secondRoute = makeTransformer(distance: 20, releaseDelay: 0.2)

        _ = try firstRoute.transform(scrollEvent(horizontal: 3), in: EventTransformerContext(device: nil))
        runFrames(for: 0.1)
        _ = try secondRoute.transform(scrollEvent(horizontal: 4), in: EventTransformerContext(device: nil))
        runFrames(for: 0.5)

        XCTAssertEqual(phases.filter { $0 == .began }.count, 1)
        XCTAssertEqual(phases.filter { $0 == .ended }.count, 1)
        XCTAssertEqual(try XCTUnwrap(outputs.last).progress, -0.5, accuracy: 0.001)
    }

    func testStepsPreferRawDeviceDeltaOverAcceleratedLines() {
        let accelerated = ScrollInput(axis: .horizontal, delta: -4.5, units: .lines)
        XCTAssertEqual(SpaceSwipeTransformer.steps(of: accelerated, rawDelta: 1), -1)
        XCTAssertEqual(SpaceSwipeTransformer.steps(of: accelerated, rawDelta: 0), -4.5)

        let continuous = ScrollInput(axis: .horizontal, delta: 30, units: .points)
        XCTAssertEqual(SpaceSwipeTransformer.steps(of: continuous, rawDelta: 0), 3)
    }

    func testConfigurationClampsValues() {
        XCTAssertEqual(Scheme.Scrolling.SpaceSwipe().effectiveDistance, 12)
        XCTAssertEqual(Scheme.Scrolling.SpaceSwipe(distance: 0).effectiveDistance, 1)
        XCTAssertEqual(Scheme.Scrolling.SpaceSwipe(distance: 1000).effectiveDistance, 200)
        XCTAssertEqual(Scheme.Scrolling.SpaceSwipe().effectiveReleaseDelay, 0.16, accuracy: 0.0001)
        XCTAssertEqual(Scheme.Scrolling.SpaceSwipe(releaseDelay: 1).effectiveReleaseDelay, 0.05, accuracy: 0.0001)
        XCTAssertFalse(Scheme.Scrolling.SpaceSwipe().isEnabled)
    }

    func testConfigurationDecodesAndMerges() throws {
        let json = #"{"spaceSwipe":{"enabled":true,"distance":24}}"#
        let decoded = try JSONDecoder().decode(Scheme.Scrolling.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.spaceSwipe.isEnabled)
        XCTAssertEqual(decoded.spaceSwipe.distance, 24)

        var merged = Scheme.Scrolling()
        Scheme.Scrolling(spaceSwipe: .init(enabled: true)).merge(into: &merged)
        Scheme.Scrolling(spaceSwipe: .init(releaseDelay: 200)).merge(into: &merged)
        XCTAssertEqual(merged.spaceSwipe, .init(enabled: true, releaseDelay: 200))
    }
}
