// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// Covers the shared retry and confirmation policy used by volatile Logitech settings.
final class HardwareSettingApplyCoordinatorTests: XCTestCase {
    private final class Scheduler {
        struct ScheduledWork {
            let delay: TimeInterval
            let work: () -> Void
        }

        private(set) var work = [ScheduledWork]()

        func schedule(delay: TimeInterval, work: @escaping () -> Void) {
            self.work.append(.init(delay: delay, work: work))
        }

        func runNext() {
            work.removeFirst().work()
        }
    }

    func testRetriesFailedApplyThenConfirmsSuccessfulApply() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1, 2],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var results = [false, true, true]
        var verificationFlags = [Bool]()

        coordinator.start { verifiesCachedValue in
            verificationFlags.append(verifiesCachedValue)
            return results.removeFirst()
        }

        XCTAssertEqual(scheduler.work.map(\.delay), [0])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [1])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [3])
        scheduler.runNext()

        XCTAssertTrue(scheduler.work.isEmpty)
        XCTAssertEqual(verificationFlags, [false, false, true])
    }

    func testRetriesFailedConfirmationWithoutRestartingApplyPhase() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1, 2],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var results = [true, false, true]
        var verificationFlags = [Bool]()

        coordinator.start { verifiesCachedValue in
            verificationFlags.append(verifiesCachedValue)
            return results.removeFirst()
        }

        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [3])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [1])
        scheduler.runNext()

        XCTAssertTrue(scheduler.work.isEmpty)
        XCTAssertEqual(verificationFlags, [false, true, true])
    }

    func testStopsAfterRetryBudgetIsExhausted() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1, 2],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var calls = 0

        coordinator.start { _ in
            calls += 1
            return false
        }

        XCTAssertEqual(scheduler.work.map(\.delay), [0])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [1])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [2])
        scheduler.runNext()

        XCTAssertEqual(calls, 3)
        XCTAssertTrue(scheduler.work.isEmpty)
    }

    func testNewRequestCancelsPreviouslyScheduledWork() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var firstRequestCalls = 0
        var secondRequestCalls = 0

        coordinator.start { _ in
            firstRequestCalls += 1
            return true
        }
        coordinator.start { _ in
            secondRequestCalls += 1
            return true
        }

        scheduler.runNext()
        scheduler.runNext()

        XCTAssertEqual(firstRequestCalls, 0)
        XCTAssertEqual(secondRequestCalls, 1)
        XCTAssertEqual(scheduler.work.map(\.delay), [3])
    }

    func testCancelPreventsScheduledWorkFromRunning() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var calls = 0

        coordinator.start { _ in
            calls += 1
            return true
        }
        coordinator.cancel()
        scheduler.runNext()

        XCTAssertEqual(calls, 0)
        XCTAssertTrue(scheduler.work.isEmpty)
    }
}
