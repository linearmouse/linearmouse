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
            logitechTeardownPolicy: .sleepRestore
        )

        intent.merge(.init(
            logitechTeardownPolicy: .restore
        ))

        XCTAssertEqual(intent.logitechTeardownPolicy, .restore)
    }

    func testSleepCannotDowngradeTerminalRestoreIntent() {
        var intent = DeviceManagerStopIntent(
            logitechTeardownPolicy: .restore
        )

        intent.merge(.init(
            logitechTeardownPolicy: .sleepRestore
        ))

        XCTAssertEqual(intent.logitechTeardownPolicy, .restore)
    }

    func testSleepControlsCompletionCannotFinishAfterTerminalUpgrade() {
        let sleep = DeviceManagerStopIntent(
            logitechTeardownPolicy: .sleepRestore
        )
        var terminal = sleep
        terminal.merge(.init(
            logitechTeardownPolicy: .restore
        ))

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: sleep), .sleepRestore)
        barrier.complete(.sleepRestore)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))

        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))
        barrier.complete(.restore)
        XCTAssertTrue(barrier.isSatisfied(for: terminal))
    }

    func testTerminalControlsBarrierRemainsSufficientAfterSleepRequest() {
        let terminal = DeviceManagerStopIntent(
            logitechTeardownPolicy: .restore
        )
        var merged = terminal
        merged.merge(.init(
            logitechTeardownPolicy: .sleepRestore
        ))

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertNil(barrier.startNeeded(for: merged))
        barrier.complete(.restore)
        XCTAssertTrue(barrier.isSatisfied(for: merged))
    }

    func testStaleSleepCompletionCannotDowngradeRestoreBarrier() {
        let sleep = DeviceManagerStopIntent(
            logitechTeardownPolicy: .sleepRestore
        )
        let restore = DeviceManagerStopIntent(
            logitechTeardownPolicy: .restore
        )

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: sleep), .sleepRestore)
        XCTAssertEqual(barrier.startNeeded(for: restore), .restore)
        barrier.complete(.restore)
        barrier.complete(.sleepRestore)

        XCTAssertEqual(barrier.highestStarted, .restore)
        XCTAssertEqual(barrier.highestCompleted, .restore)
        XCTAssertTrue(barrier.isSatisfied(for: restore))
    }

    func testAbandonDoesNotCreateAnAsynchronousControlsBarrier() {
        let abandon = DeviceManagerStopIntent(
            logitechTeardownPolicy: .abandon
        )

        XCTAssertEqual(abandon.logitechTeardownPolicy, .abandon)

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: abandon), .abandon)
        barrier.complete(.abandon)
        XCTAssertTrue(barrier.isSatisfied(for: abandon))
        XCTAssertNil(barrier.startNeeded(for: abandon))
    }

    func testTerminalControlsPolicyUsesRestorePendingAdmission() {
        let terminal = DeviceManagerStopIntent(
            logitechTeardownPolicy: .restore
        )

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(terminal.logitechTeardownPolicy, .restore)
        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))
    }

    func testLateCompletionCannotSatisfyANewerStopRequest() {
        let intent = DeviceManagerStopIntent(logitechTeardownPolicy: .sleepRestore)
        let previous = DeviceManagerStopRequest(intent: intent)
        let current = DeviceManagerStopRequest(intent: intent)

        XCTAssertEqual(previous.logitechBarrier.startNeeded(for: intent), .sleepRestore)
        XCTAssertEqual(current.logitechBarrier.startNeeded(for: intent), .sleepRestore)

        previous.logitechBarrier.complete(.sleepRestore)

        XCTAssertTrue(previous.logitechBarrier.isSatisfied(for: intent))
        XCTAssertFalse(current.logitechBarrier.isSatisfied(for: intent))
    }

    func testTerminalIdentityRequiresMatchingStableSerial() {
        let expected = receiverIdentity(serial: "AAA", productID: 1)

        XCTAssertTrue(DeviceManager.terminalIdentityMatches(
            expected: expected,
            fresh: receiverIdentity(serial: "aaa", productID: 2)
        ))
        XCTAssertFalse(DeviceManager.terminalIdentityMatches(
            expected: expected,
            fresh: receiverIdentity(serial: "BBB", productID: 1)
        ))
    }

    func testUnkeyedTerminalIdentityFailsClosedDespiteMatchingTargetShape() {
        let expected = receiverIdentity(serial: nil, productID: 1)

        XCTAssertFalse(DeviceManager.terminalIdentityMatches(
            expected: expected,
            fresh: expected
        ))
    }

    func testMissingSerialSentinelsFailClosedForTerminalIdentity() {
        for serial in ["00000000", "FF-FF-FF-FF"] {
            let identity = receiverIdentity(serial: serial, productID: 1)
            XCTAssertFalse(DeviceManager.terminalIdentityMatches(
                expected: identity,
                fresh: identity
            ))
        }
    }

    private func receiverIdentity(
        serial: String?,
        productID: Int
    ) -> ReceiverLogicalDeviceIdentity {
        .init(
            receiverLocationID: 1,
            slot: 2,
            kind: .mouse,
            name: "Mouse",
            serialNumber: serial,
            productID: productID,
            batteryLevel: nil
        )
    }
}
