// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class DeviceLifecycleAdmissionTests: XCTestCase {
    func testQueuedControlsEnableIsRejectedAfterStopBegins() {
        let lifecycle = DeviceManagerLifecycleState.stopping

        XCTAssertFalse(lifecycle.allowsDeviceWork)
    }

    func testDeviceAddedIsRejectedWhileFinishing() {
        let lifecycle = DeviceManagerLifecycleState.finishing

        XCTAssertFalse(lifecycle.allowsDeviceWork)
    }

    func testResumeCannotRestartAfterTerminationCleanupBegins() {
        var lifecycle = AppLifecycleAdmission()
        lifecycle.sessionActive = true
        lifecycle.sleeping = false
        lifecycle.terminationCleanupStarted = true

        XCTAssertFalse(lifecycle.allowsStart)
    }

    func testOnlyRunningManagerAdmitsDeviceWork() {
        XCTAssertFalse(DeviceManagerLifecycleState.stopped.allowsDeviceWork)
        XCTAssertTrue(DeviceManagerLifecycleState.running.allowsDeviceWork)
        XCTAssertFalse(DeviceManagerLifecycleState.stopping.allowsDeviceWork)
        XCTAssertFalse(DeviceManagerLifecycleState.finishing.allowsDeviceWork)
    }

    func testSleepIntentIsUpgradedByTerminalRestore() {
        var intent = DeviceManagerStopIntent(
            restoringHighResolutionWheel: false,
            restoringLogitechControls: false,
            applyingSleepHiResPolicy: true
        )

        intent.merge(.init(
            restoringHighResolutionWheel: true,
            restoringLogitechControls: true,
            applyingSleepHiResPolicy: false
        ))

        XCTAssertTrue(intent.restoresHighResolutionWheel)
        XCTAssertTrue(intent.restoresLogitechControls)
        XCTAssertFalse(intent.appliesSleepHiResPolicy)
        XCTAssertFalse(intent.appliesSleepControlsPolicy)
    }

    func testSleepCannotDowngradeTerminalRestoreIntent() {
        var intent = DeviceManagerStopIntent(
            restoringHighResolutionWheel: true,
            restoringLogitechControls: true,
            applyingSleepHiResPolicy: false
        )

        intent.merge(.init(
            restoringHighResolutionWheel: false,
            restoringLogitechControls: false,
            applyingSleepHiResPolicy: true
        ))

        XCTAssertTrue(intent.restoresHighResolutionWheel)
        XCTAssertTrue(intent.restoresLogitechControls)
        XCTAssertFalse(intent.appliesSleepHiResPolicy)
        XCTAssertFalse(intent.appliesSleepControlsPolicy)
    }

    func testSleepControlsCompletionCannotFinishAfterTerminalUpgrade() {
        let sleep = DeviceManagerStopIntent(
            restoringHighResolutionWheel: false,
            restoringLogitechControls: false,
            applyingSleepHiResPolicy: true
        )
        var terminal = sleep
        terminal.merge(.init(
            restoringHighResolutionWheel: true,
            restoringLogitechControls: true,
            applyingSleepHiResPolicy: false
        ))

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: sleep), .sleep)
        barrier.complete(.sleep)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))

        XCTAssertEqual(barrier.startNeeded(for: terminal), .normal)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))
        barrier.complete(.normal)
        XCTAssertTrue(barrier.isSatisfied(for: terminal))
    }

    func testTerminalControlsBarrierRemainsSufficientAfterSleepRequest() {
        let terminal = DeviceManagerStopIntent(
            restoringHighResolutionWheel: true,
            restoringLogitechControls: true,
            applyingSleepHiResPolicy: false
        )
        var merged = terminal
        merged.merge(.init(
            restoringHighResolutionWheel: false,
            restoringLogitechControls: false,
            applyingSleepHiResPolicy: true
        ))

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: terminal), .normal)
        XCTAssertNil(barrier.startNeeded(for: merged))
        barrier.complete(.normal)
        XCTAssertTrue(barrier.isSatisfied(for: merged))
    }
}
