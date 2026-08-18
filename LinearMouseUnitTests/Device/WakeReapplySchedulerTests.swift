// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class WakeReapplySchedulerTests: XCTestCase {
    /// Collects the work items a scheduler hands out so a test can fire them by hand.
    private final class ScheduleRecorder {
        private(set) var delays: [TimeInterval] = []
        private(set) var workItems: [DispatchWorkItem] = []

        func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) -> DispatchWorkItem {
            let workItem = DispatchWorkItem(block: block)
            delays.append(delay)
            workItems.append(workItem)
            return workItem
        }

        /// Runs every work item that has not been cancelled, the way the main queue would.
        func fireAll() {
            for workItem in workItems where !workItem.isCancelled {
                workItem.perform()
            }
        }
    }

    func testRestartSchedulesOneRunPerAttemptAtAFlatInterval() {
        let recorder = ScheduleRecorder()
        let scheduler = WakeReapplyScheduler(interval: 1, attempts: 3, schedule: recorder.schedule)

        var runCount = 0
        scheduler.restart { runCount += 1 }

        XCTAssertEqual(recorder.delays, [1, 2, 3])
        XCTAssertEqual(runCount, 0, "Nothing should run before the delays elapse")

        recorder.fireAll()

        XCTAssertEqual(runCount, 3)
    }

    func testDurationCoversTheWholeSettleWindow() {
        let scheduler = WakeReapplyScheduler(interval: 1, attempts: 30) { _, block in
            DispatchWorkItem(block: block)
        }

        XCTAssertEqual(scheduler.duration, 30)
    }

    func testRestartCancelsThePendingSeries() {
        let recorder = ScheduleRecorder()
        let scheduler = WakeReapplyScheduler(interval: 1, attempts: 2, schedule: recorder.schedule)

        var firstWakeRuns = 0
        scheduler.restart { firstWakeRuns += 1 }

        var secondWakeRuns = 0
        scheduler.restart { secondWakeRuns += 1 }

        recorder.fireAll()

        XCTAssertEqual(firstWakeRuns, 0, "A second wake should supersede the pending series")
        XCTAssertEqual(secondWakeRuns, 2)
    }

    func testCancelStopsPendingRuns() {
        let recorder = ScheduleRecorder()
        let scheduler = WakeReapplyScheduler(interval: 1, attempts: 2, schedule: recorder.schedule)

        var runCount = 0
        scheduler.restart { runCount += 1 }
        scheduler.cancel()

        recorder.fireAll()

        XCTAssertEqual(runCount, 0)
    }

    func testDefaultsRetryOftenEnoughToBoundTheWrongPointerFeel() {
        XCTAssertEqual(WakeReapplyScheduler.defaultInterval, 1)
        XCTAssertGreaterThan(WakeReapplyScheduler.defaultAttempts, 1)

        let scheduler = WakeReapplyScheduler()

        XCTAssertEqual(scheduler.duration, 30)
    }
}
