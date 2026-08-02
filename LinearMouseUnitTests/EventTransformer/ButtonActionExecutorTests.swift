// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

private final class ButtonActionTestTimerScheduler {
    final class ScheduledTimer {
        let interval: TimeInterval
        let repeats: Bool
        let handler: () -> Void
        var isActive = true

        init(interval: TimeInterval, repeats: Bool, handler: @escaping () -> Void) {
            self.interval = interval
            self.repeats = repeats
            self.handler = handler
        }
    }

    private(set) var timers = [ScheduledTimer]()

    func schedule(
        interval: TimeInterval,
        repeats: Bool,
        handler: @escaping () -> Void
    ) -> ButtonActionExecutor.TimerToken {
        let timer = ScheduledTimer(interval: interval, repeats: repeats, handler: handler)
        timers.append(timer)
        return .init {
            timer.isActive = false
        }
    }

    func fire(_ timer: ScheduledTimer) {
        guard timer.isActive else {
            return
        }
        if !timer.repeats {
            timer.isActive = false
        }
        timer.handler()
    }
}

final class ButtonActionExecutorTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping

    private let repeatAction = Mapping.PressAction(
        action: .arg0(.none),
        behavior: .repeat
    )

    func testRepeatSchedulesSystemDelayAndCancelsOnRelease() throws {
        let runtimeState = ButtonActionExecutor.RuntimeState()
        let scheduler = ButtonActionTestTimerScheduler()
        let executor = makeExecutor(runtimeState: runtimeState, scheduler: scheduler)
        let buttons: Set<Mapping.Button> = [.mouse(4)]

        executor.beginPress(repeatAction, buttons: buttons, targetBundleIdentifier: nil)

        let delayTimer = try XCTUnwrap(scheduler.timers.first)
        XCTAssertEqual(delayTimer.interval, 0.4)
        XCTAssertFalse(delayTimer.repeats)
        XCTAssertTrue(delayTimer.isActive)
        XCTAssertNotNil(runtimeState.repeatTimers[buttons])

        executor.endPress(repeatAction, buttons: buttons)

        XCTAssertFalse(delayTimer.isActive)
        XCTAssertTrue(runtimeState.repeatTimers.isEmpty)
    }

    func testRepeatSwitchesFromDelayToRepeatingTimer() throws {
        let runtimeState = ButtonActionExecutor.RuntimeState()
        let scheduler = ButtonActionTestTimerScheduler()
        let executor = makeExecutor(runtimeState: runtimeState, scheduler: scheduler)
        let buttons: Set<Mapping.Button> = [.mouse(4)]

        executor.beginPress(repeatAction, buttons: buttons, targetBundleIdentifier: nil)
        try scheduler.fire(XCTUnwrap(scheduler.timers.first))

        XCTAssertEqual(scheduler.timers.count, 2)
        let repeatingTimer = scheduler.timers[1]
        XCTAssertEqual(repeatingTimer.interval, 0.05)
        XCTAssertTrue(repeatingTimer.repeats)
        XCTAssertTrue(repeatingTimer.isActive)

        executor.endPress(repeatAction, buttons: buttons)
        XCTAssertFalse(repeatingTimer.isActive)
    }

    func testIndependentRepeatsHaveIndependentTimers() {
        let runtimeState = ButtonActionExecutor.RuntimeState()
        let scheduler = ButtonActionTestTimerScheduler()
        let executor = makeExecutor(runtimeState: runtimeState, scheduler: scheduler)
        let firstButtons: Set<Mapping.Button> = [.mouse(4)]
        let secondButtons: Set<Mapping.Button> = [.mouse(5)]

        executor.beginPress(repeatAction, buttons: firstButtons, targetBundleIdentifier: nil)
        executor.beginPress(repeatAction, buttons: secondButtons, targetBundleIdentifier: nil)

        XCTAssertEqual(scheduler.timers.count, 2)
        executor.endPress(repeatAction, buttons: firstButtons)
        XCTAssertFalse(scheduler.timers[0].isActive)
        XCTAssertTrue(scheduler.timers[1].isActive)
        XCTAssertNil(runtimeState.repeatTimers[firstButtons])
        XCTAssertNotNil(runtimeState.repeatTimers[secondButtons])

        executor.endPress(repeatAction, buttons: secondButtons)
        XCTAssertFalse(scheduler.timers[1].isActive)
        XCTAssertTrue(runtimeState.repeatTimers.isEmpty)
    }

    func testDisabledSystemRepeatDefersOneActionUntilRelease() {
        let runtimeState = ButtonActionExecutor.RuntimeState()
        let scheduler = ButtonActionTestTimerScheduler()
        let executor = ButtonActionExecutor(
            runtimeState: runtimeState,
            repeatTimingProvider: { (delay: 0, interval: 0) },
            scheduleTimer: scheduler.schedule
        )
        let buttons: Set<Mapping.Button> = [.mouse(4)]

        executor.beginPress(repeatAction, buttons: buttons, targetBundleIdentifier: nil)

        XCTAssertTrue(scheduler.timers.isEmpty)
        XCTAssertNotNil(runtimeState.pendingReleaseActions[buttons])

        executor.endPress(repeatAction, buttons: buttons)
        XCTAssertTrue(runtimeState.pendingReleaseActions.isEmpty)
    }

    private func makeExecutor(
        runtimeState: ButtonActionExecutor.RuntimeState,
        scheduler: ButtonActionTestTimerScheduler
    ) -> ButtonActionExecutor {
        ButtonActionExecutor(
            runtimeState: runtimeState,
            repeatTimingProvider: { (delay: 0.4, interval: 0.05) },
            scheduleTimer: scheduler.schedule
        )
    }
}
