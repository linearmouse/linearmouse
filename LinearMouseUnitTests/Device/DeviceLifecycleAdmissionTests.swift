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
        XCTAssertEqual(lifecycle.target, .stopped)
    }

    func testInactiveSessionDominatesSleep() {
        var lifecycle = AppLifecycleAdmission()
        lifecycle.sessionActive = false
        lifecycle.sleeping = true

        XCTAssertEqual(lifecycle.target, .stopped)
    }

    func testTerminationDominatesActiveAwakeSession() {
        var lifecycle = AppLifecycleAdmission()
        lifecycle.terminationCleanupStarted = true

        XCTAssertEqual(lifecycle.target, .stopped)
    }

    func testActiveSleepingSessionTargetsSuspension() {
        var lifecycle = AppLifecycleAdmission()
        lifecycle.sleeping = true

        XCTAssertEqual(lifecycle.target, .suspended)
        XCTAssertFalse(lifecycle.allowsStart)
    }

    func testActiveAwakeSessionTargetsRunning() {
        let lifecycle = AppLifecycleAdmission()

        XCTAssertEqual(lifecycle.target, .running)
        XCTAssertTrue(lifecycle.allowsStart)
    }

    func testSessionBecomeActiveBeforeWakeRemainsSuspended() {
        var lifecycle = AppLifecycleAdmission()

        lifecycle.sleeping = true
        XCTAssertEqual(lifecycle.target, .suspended)

        lifecycle.sessionActive = true
        XCTAssertEqual(lifecycle.target, .suspended)

        lifecycle.sleeping = false
        XCTAssertEqual(lifecycle.target, .running)
    }

    func testInactiveSleepSequenceDoesNotRunUntilSessionReturns() {
        var lifecycle = AppLifecycleAdmission()

        lifecycle.sleeping = true
        lifecycle.sessionActive = false
        XCTAssertEqual(lifecycle.target, .stopped)

        lifecycle.sleeping = false
        XCTAssertEqual(lifecycle.target, .stopped)

        lifecycle.sessionActive = true
        XCTAssertEqual(lifecycle.target, .running)
    }

    func testOnlyRunningManagerAdmitsDeviceWork() {
        XCTAssertFalse(DeviceManagerLifecycleState.stopped.allowsDeviceWork)
        XCTAssertTrue(DeviceManagerLifecycleState.running.allowsDeviceWork)
        XCTAssertFalse(DeviceManagerLifecycleState.suspending.allowsDeviceWork)
        XCTAssertFalse(DeviceManagerLifecycleState.suspended.allowsDeviceWork)
        XCTAssertFalse(DeviceManagerLifecycleState.stopping.allowsDeviceWork)
        XCTAssertFalse(DeviceManagerLifecycleState.finishing.allowsDeviceWork)
    }

    func testSuspendedManagerStillAdmitsTopology() {
        XCTAssertTrue(DeviceManagerLifecycleState.running.allowsDeviceTopology)
        XCTAssertTrue(DeviceManagerLifecycleState.suspending.allowsDeviceTopology)
        XCTAssertTrue(DeviceManagerLifecycleState.suspended.allowsDeviceTopology)
        XCTAssertFalse(DeviceManagerLifecycleState.stopped.allowsDeviceTopology)
        XCTAssertFalse(DeviceManagerLifecycleState.stopping.allowsDeviceTopology)
        XCTAssertFalse(DeviceManagerLifecycleState.finishing.allowsDeviceTopology)
    }

    func testSuspensionCanResumeOnlyOnce() {
        let request = DeviceManagerSuspensionRequest()

        XCTAssertTrue(request.claimResume())
        XCTAssertFalse(request.claimResume())
        XCTAssertEqual(request.disposition, .resumed)
    }

    func testSupersededSuspensionCannotResume() {
        let request = DeviceManagerSuspensionRequest()

        request.supersede()

        XCTAssertFalse(request.claimResume())
        XCTAssertEqual(request.disposition, .superseded)
    }

    func testFastWakeOfPreviousRequestDoesNotClaimNextSuspension() {
        let previous = DeviceManagerSuspensionRequest()
        let current = DeviceManagerSuspensionRequest()

        XCTAssertTrue(previous.claimResume())
        XCTAssertTrue(current.claimResume())
        XCTAssertFalse(previous.claimResume())
        XCTAssertFalse(current.claimResume())
    }

    func testTerminalSupersedesAlreadyResumedCleanupRequest() {
        let request = DeviceManagerSuspensionRequest()
        XCTAssertTrue(request.claimResume())

        request.supersede()

        XCTAssertEqual(request.disposition, .superseded)
        XCTAssertFalse(request.claimResume())
    }

    func testAbandonIntentIsUpgradedByTerminalRestore() {
        var intent = DeviceManagerStopIntent(
            logitechTeardownPolicy: .abandon
        )

        intent.merge(.init(
            logitechTeardownPolicy: .restore
        ))

        XCTAssertEqual(intent.logitechTeardownPolicy, .restore)
    }

    func testAbandonCannotDowngradeTerminalRestoreIntent() {
        var intent = DeviceManagerStopIntent(
            logitechTeardownPolicy: .restore
        )

        intent.merge(.init(
            logitechTeardownPolicy: .abandon
        ))

        XCTAssertEqual(intent.logitechTeardownPolicy, .restore)
    }

    func testAbandonCompletionCannotFinishAfterTerminalUpgrade() {
        let abandon = DeviceManagerStopIntent(
            logitechTeardownPolicy: .abandon
        )
        var terminal = abandon
        terminal.merge(.init(
            logitechTeardownPolicy: .restore
        ))

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: abandon), .abandon)
        barrier.complete(.abandon)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))

        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertFalse(barrier.isSatisfied(for: terminal))
        barrier.complete(.restore)
        XCTAssertTrue(barrier.isSatisfied(for: terminal))
    }

    func testTerminalControlsBarrierRemainsSufficientAfterAbandonRequest() {
        let terminal = DeviceManagerStopIntent(
            logitechTeardownPolicy: .restore
        )
        var merged = terminal
        merged.merge(.init(
            logitechTeardownPolicy: .abandon
        ))

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: terminal), .restore)
        XCTAssertNil(barrier.startNeeded(for: merged))
        barrier.complete(.restore)
        XCTAssertTrue(barrier.isSatisfied(for: merged))
    }

    func testStaleAbandonCompletionCannotDowngradeRestoreBarrier() {
        let abandon = DeviceManagerStopIntent(
            logitechTeardownPolicy: .abandon
        )
        let restore = DeviceManagerStopIntent(
            logitechTeardownPolicy: .restore
        )

        var barrier = DeviceManagerLogitechStopBarrier()
        XCTAssertEqual(barrier.startNeeded(for: abandon), .abandon)
        XCTAssertEqual(barrier.startNeeded(for: restore), .restore)
        barrier.complete(.restore)
        barrier.complete(.abandon)

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
        let intent = DeviceManagerStopIntent(logitechTeardownPolicy: .restore)
        let previous = DeviceManagerStopRequest(intent: intent)
        let current = DeviceManagerStopRequest(intent: intent)

        XCTAssertEqual(previous.logitechBarrier.startNeeded(for: intent), .restore)
        XCTAssertEqual(current.logitechBarrier.startNeeded(for: intent), .restore)

        previous.logitechBarrier.complete(.restore)

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
