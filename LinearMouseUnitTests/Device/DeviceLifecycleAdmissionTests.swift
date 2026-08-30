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
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        )

        intent.merge(.init(
            restoringHighResolutionWheel: true,
            applyingSleepHiResPolicy: false,
            controlsTeardownPolicy: .restore
        ))

        XCTAssertTrue(intent.restoresHighResolutionWheel)
        XCTAssertFalse(intent.appliesSleepHiResPolicy)
        XCTAssertEqual(intent.controlsTeardownPolicy, .restore)
    }

    func testSleepCannotDowngradeTerminalRestoreIntent() {
        var intent = DeviceManagerStopIntent(
            restoringHighResolutionWheel: true,
            applyingSleepHiResPolicy: false,
            controlsTeardownPolicy: .restore
        )

        intent.merge(.init(
            restoringHighResolutionWheel: false,
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        ))

        XCTAssertTrue(intent.restoresHighResolutionWheel)
        XCTAssertFalse(intent.appliesSleepHiResPolicy)
        XCTAssertEqual(intent.controlsTeardownPolicy, .restore)
    }

    func testSleepControlsCompletionCannotFinishAfterTerminalUpgrade() {
        let sleep = DeviceManagerStopIntent(
            restoringHighResolutionWheel: false,
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        )
        var terminal = sleep
        terminal.merge(.init(
            restoringHighResolutionWheel: true,
            applyingSleepHiResPolicy: false,
            controlsTeardownPolicy: .restore
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
            applyingSleepHiResPolicy: false,
            controlsTeardownPolicy: .restore
        )
        var merged = terminal
        merged.merge(.init(
            restoringHighResolutionWheel: false,
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        ))

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertNil(barrier.startNeeded(for: merged))
        barrier.complete(.restore)
        XCTAssertTrue(barrier.isSatisfied(for: merged))
    }

    func testStaleSleepCompletionCannotDowngradeRestoreBarrier() {
        let sleep = DeviceManagerStopIntent(
            restoringHighResolutionWheel: false,
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve
        )
        let restore = DeviceManagerStopIntent(
            restoringHighResolutionWheel: true,
            applyingSleepHiResPolicy: false,
            controlsTeardownPolicy: .restore
        )

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: sleep), .sleepPreserve)
        XCTAssertEqual(barrier.startNeeded(for: restore), .restore)
        barrier.complete(.restore)
        barrier.complete(.sleepPreserve)

        XCTAssertEqual(barrier.highestStarted, .restore)
        XCTAssertEqual(barrier.highestCompleted, .restore)
        XCTAssertTrue(barrier.isSatisfied(for: restore))
    }

    func testAbandonDoesNotCreateAnAsynchronousControlsBarrier() {
        let abandon = DeviceManagerStopIntent(
            restoringHighResolutionWheel: false,
            applyingSleepHiResPolicy: false,
            controlsTeardownPolicy: .abandon
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
            applyingSleepHiResPolicy: false,
            controlsTeardownPolicy: .restore
        )

        var barrier = DeviceManagerControlsStopBarrier()
        XCTAssertEqual(terminal.controlsTeardownPolicy, .restore)
        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))
    }
}
