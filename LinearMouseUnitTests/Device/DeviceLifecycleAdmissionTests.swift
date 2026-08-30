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
}
