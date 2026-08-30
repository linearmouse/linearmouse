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
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        )

        intent.merge(.init(
            restoringHighResolutionWheel: true,
            restoringLogitechControls: true,
            applyingSleepHiResPolicy: false
        ))

        XCTAssertTrue(intent.restoresHighResolutionWheel)
        XCTAssertFalse(intent.appliesSleepHiResPolicy)
        XCTAssertEqual(intent.controlsTeardownPolicy, .restore)
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
        XCTAssertFalse(intent.appliesSleepHiResPolicy)
        XCTAssertEqual(intent.controlsTeardownPolicy, .restore)
    }

    func testSleepControlsCompletionCannotFinishAfterTerminalUpgrade() {
        let sleep = DeviceManagerStopIntent(
            restoringHighResolutionWheel: false,
            restoringLogitechControls: false,
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        )
        var terminal = sleep
        terminal.merge(.init(
            restoringHighResolutionWheel: true,
            restoringLogitechControls: true,
            applyingSleepHiResPolicy: false
        ))

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: sleep), .sleepPreserve)
        barrier.complete(.sleepPreserve)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))

        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))
        barrier.complete(.restore)
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
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        ))

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertNil(barrier.startNeeded(for: merged))
        barrier.complete(.restore)
        XCTAssertTrue(barrier.isSatisfied(for: merged))
    }

    func testAbandonDoesNotCreateAnAsynchronousControlsBarrier() {
        let abandon = DeviceManagerStopIntent(
            restoringHighResolutionWheel: false,
            restoringLogitechControls: false,
            applyingSleepHiResPolicy: false
        )

        XCTAssertEqual(abandon.controlsTeardownPolicy, .abandon)

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: abandon), .abandon)
        barrier.complete(.abandon)
        XCTAssertTrue(barrier.isSatisfied(for: abandon))
        XCTAssertNil(barrier.startNeeded(for: abandon))
    }

    func testTerminalControlsPolicyUsesRestorePendingAdmission() {
        let terminal = DeviceManagerStopIntent(
            restoringHighResolutionWheel: true,
            restoringLogitechControls: true,
            applyingSleepHiResPolicy: false
        )

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(terminal.controlsTeardownPolicy, .restore)
        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))
    }
}
