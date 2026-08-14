// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

private final class TestClickDebounceTimerScheduler {
    private final class ScheduledTimer {
        let deadline: TimeInterval
        let handler: () -> Void
        var active = true

        init(deadline: TimeInterval, handler: @escaping () -> Void) {
            self.deadline = deadline
            self.handler = handler
        }
    }

    private(set) var now: TimeInterval = 0
    private var timers = [ScheduledTimer]()
    private(set) var scheduledIntervals = [TimeInterval]()

    var activeTimerCount: Int {
        timers.count(where: \.active)
    }

    var nowNanoseconds: UInt64 {
        UInt64(now * 1_000_000_000)
    }

    func schedule(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> LibinputClickDebouncingTransformer.TimerToken {
        scheduledIntervals.append(interval)
        let timer = ScheduledTimer(deadline: now + interval, handler: handler)
        timers.append(timer)
        return .init {
            timer.active = false
        }
    }

    func advance(by interval: TimeInterval) {
        let target = now + interval

        while let timer = timers
            .filter(\.active)
            .filter({ $0.deadline <= target })
            .min(by: { $0.deadline < $1.deadline }) {
            now = timer.deadline
            timer.active = false
            timer.handler()
        }

        now = target
    }

    func elapseWithoutFiring(by interval: TimeInterval) {
        now += interval
    }

    func invokeHandler(at index: Int) {
        timers[index].handler()
    }
}

private final class RecordingEventTransformer: EventTransformer {
    private(set) var eventTypes = [CGEventType]()

    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        eventTypes.append(event.type)
        let eventNumber = event.getIntegerValueField(.mouseEventNumber)
        event.setIntegerValueField(.mouseEventNumber, value: eventNumber + 1000)
        return event
    }
}

private func makeMouseButtonEvent(
    button: CGMouseButton,
    pressed: Bool,
    eventNumber: Int64
) throws -> CGEvent {
    let event = try XCTUnwrap(CGEvent(
        mouseEventSource: nil,
        mouseType: button.fixedCGEventType(of: pressed ? .leftMouseDown : .leftMouseUp),
        mouseCursorPosition: .zero,
        mouseButton: button
    ))
    event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
    event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
    return event
}

final class ClickDebouncingTransformerTests: XCTestCase {
    func testLegacyModeSuppressesRapidPressButForwardsFirstRelease() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 2),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeCanResetTimerOnRelease() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: true
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 100_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeSuppressesPhantomReleaseFromContactBounce() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 51_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeStillForwardsIntentionalRapidClickRelease() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 60_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 60_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 60_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeSuppressesBounceUpAfterSuppressedBounceDown() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 15_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeSuppressedReleaseStillResetsPressTimerWhenEnabled() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: true
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 45_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeCountsMultipleForwardedPressesWithoutRelease() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 60_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 5_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 5_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeReleaseDebounceWindowAnchorsAtLastRelease() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 100_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeSuppressedReleaseExtendsDebounceWindow() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 40_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 40_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeReleaseAtExactTimeoutBoundaryIsSuppressed() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 100_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 50_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeForwardsReleaseClosingForwardedPressInsideWindow() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.05,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 100_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 5_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 45_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testLegacyModeForwardsRealReleaseAfterBounceChatterWithLargeTimeout() throws {
        var now: UInt64 = 1_000_000_000
        let transformer = ClickDebouncingTransformer(
            for: .left,
            timeout: 0.1,
            resetTimerOnMouseUp: false
        ) { now }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        now += 10_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        now += 20_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 3),
            in: .init(device: nil)
        ))
        now += 30_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
        now += 30_000_000
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 5),
            in: .init(device: nil)
        ))
        now += 20_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 6),
            in: .init(device: nil)
        ))
        now += 40_000_000
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 7),
            in: .init(device: nil)
        ))
    }
}

final class LibinputClickDebouncingTransformerTests: XCTestCase {
    func testUsesLibinputFixedBounceAndSpuriousTimeouts() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        let transformer = makeTransformer(timerScheduler: timerScheduler)

        _ = try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        )
        XCTAssertEqual(timerScheduler.scheduledIntervals, [0.025])

        timerScheduler.advance(by: 0.025)
        _ = try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        )
        XCTAssertEqual(timerScheduler.scheduledIntervals, [0.025, 0.025, 0.012])
    }

    func testElapsedDeadlineIsAppliedBeforeALateTimerWakeup() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedTypes = [CGEventType]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedTypes.append($0.type)
        }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))

        timerScheduler.elapseWithoutFiring(by: 0.026)

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))
        XCTAssertEqual(emittedTypes, [.leftMouseUp])
    }

    func testElapsedSpuriousDeadlineIsAppliedBeforeALateTimerWakeup() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedTypes = [CGEventType]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedTypes.append($0.type)
        }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        timerScheduler.advance(by: 0.025)
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))

        timerScheduler.elapseWithoutFiring(by: 0.013)

        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
        XCTAssertEqual(emittedTypes, [.leftMouseDown])
    }

    func testEventBeforeBounceDeadlineRemainsPartOfBounceSequence() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        let transformer = makeTransformer(timerScheduler: timerScheduler)

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))

        timerScheduler.elapseWithoutFiring(by: 0.024999)

        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))
    }

    func testCancelledTimerHandlerCannotAdvanceStateMachine() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedTypes = [CGEventType]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedTypes.append($0.type)
        }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .right, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))

        timerScheduler.elapseWithoutFiring(by: 0.050)
        timerScheduler.invokeHandler(at: 1)

        XCTAssertEqual(emittedTypes, [.leftMouseUp])
    }

    func testQuickClickDelaysReleaseAndPreservesEventMetadata() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedEvents = [CGEvent]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedEvents.append($0)
        }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 41),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 42),
            in: .init(device: nil)
        ))
        XCTAssertTrue(emittedEvents.isEmpty)

        timerScheduler.advance(by: 0.025)

        XCTAssertEqual(emittedEvents.map(\.type), [.leftMouseUp])
        XCTAssertEqual(emittedEvents.first?.getIntegerValueField(.mouseEventNumber), 42)
    }

    func testPressReleasePressBounceStillForwardsFinalRelease() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        let transformer = makeTransformer(timerScheduler: timerScheduler)

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))

        timerScheduler.advance(by: 0.025)

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testBounceTimerRestartsForEachEventInLongBounceSequence() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedTypes = [CGEventType]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedTypes.append($0.type)
        }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        timerScheduler.advance(by: 0.015)
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        timerScheduler.advance(by: 0.015)
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))

        timerScheduler.advance(by: 0.025)

        XCTAssertTrue(emittedTypes.isEmpty)
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
    }

    func testSpuriousModeFiltersContactLossButEmitsFinalRelease() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedTypes = [CGEventType]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedTypes.append($0.type)
        }

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        ))
        timerScheduler.advance(by: 0.025)
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))
        timerScheduler.advance(by: 0.012)
        XCTAssertEqual(emittedTypes, [.leftMouseDown])

        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 4),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 5),
            in: .init(device: nil)
        ))
        timerScheduler.advance(by: 0.012)
        XCTAssertEqual(emittedTypes, [.leftMouseDown])

        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 6),
            in: .init(device: nil)
        ))
        timerScheduler.advance(by: 0.012)
        XCTAssertEqual(emittedTypes, [.leftMouseDown, .leftMouseUp])
    }

    func testOtherButtonFlushesPendingReleaseBeforePassingThrough() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedTypes = [CGEventType]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedTypes.append($0.type)
        }

        _ = try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        )
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .right, pressed: true, eventNumber: 3),
            in: .init(device: nil)
        ))

        XCTAssertEqual(emittedTypes, [.leftMouseUp])
        XCTAssertEqual(timerScheduler.activeTimerCount, 0)
    }

    func testMultipleButtonDebouncersFlushPendingReleaseBeforeOtherButtonPress() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        let leftDebouncer = makeTransformer(button: .left, timerScheduler: timerScheduler)
        let rightDebouncer = makeTransformer(button: .right, timerScheduler: timerScheduler)
        let transformers: [EventTransformer] = [leftDebouncer, rightDebouncer]
        var postedEventNumbers = [Int64]()
        let context = EventTransformerContext(device: nil) {
            postedEventNumbers.append($0.getIntegerValueField(.mouseEventNumber))
        }

        XCTAssertNotNil(try transformers.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: context
        ))
        XCTAssertNil(try transformers.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: context
        ))

        let rightPress = try XCTUnwrap(try transformers.transform(
            makeMouseButtonEvent(button: .right, pressed: true, eventNumber: 3),
            in: context
        ))

        XCTAssertEqual(rightPress.type, .rightMouseDown)
        XCTAssertEqual(postedEventNumbers, [2])
    }

    func testDeactivateFlushesPendingReleaseAndCancelsTimers() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        var emittedTypes = [CGEventType]()
        let transformer = makeTransformer(timerScheduler: timerScheduler) {
            emittedTypes.append($0.type)
        }

        _ = try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: .init(device: nil)
        )
        XCTAssertNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: .init(device: nil)
        ))

        transformer.deactivate()

        XCTAssertEqual(emittedTypes, [.leftMouseUp])
        XCTAssertEqual(timerScheduler.activeTimerCount, 0)
    }

    func testUnmatchedReleasePassesThrough() throws {
        let transformer = makeTransformer(timerScheduler: TestClickDebounceTimerScheduler())

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 1),
            in: .init(device: nil)
        ))
    }

    func testDelayedEventContinuesThroughRemainingTransformers() throws {
        let timerScheduler = TestClickDebounceTimerScheduler()
        let debouncer = makeTransformer(timerScheduler: timerScheduler)
        let recorder = RecordingEventTransformer()
        let transformers: [EventTransformer] = [debouncer, recorder]
        var postedEventNumbers = [Int64]()
        let context = EventTransformerContext(device: nil) {
            postedEventNumbers.append($0.getIntegerValueField(.mouseEventNumber))
        }

        let press = try XCTUnwrap(try transformers.transform(
            makeMouseButtonEvent(button: .left, pressed: true, eventNumber: 1),
            in: context
        ))
        XCTAssertEqual(press.getIntegerValueField(.mouseEventNumber), 1001)
        XCTAssertNil(try transformers.transform(
            makeMouseButtonEvent(button: .left, pressed: false, eventNumber: 2),
            in: context
        ))

        timerScheduler.advance(by: 0.025)

        XCTAssertEqual(recorder.eventTypes, [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(postedEventNumbers, [1002])
    }

    private func makeTransformer(
        button: CGMouseButton = .left,
        timerScheduler: TestClickDebounceTimerScheduler,
        eventSink: @escaping (CGEvent) -> Void = { _ in }
    ) -> LibinputClickDebouncingTransformer {
        LibinputClickDebouncingTransformer(
            for: button,
            scheduleTimer: timerScheduler.schedule,
            monotonicClock: { timerScheduler.nowNanoseconds },
            eventSink: eventSink
        )
    }
}
