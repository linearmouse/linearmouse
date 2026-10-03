// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// Covers desired-state diffing and forced wake/reconnect replay.
final class LogitechDeviceSettingsReconcilerTests: XCTestCase {
    private final class Device: LogitechDeviceSettingsTarget {
        var isRemoved = false
        var isLogitechSensorDPIApplyRunning = false
        var isLogitechHighResolutionWheelApplyRunning = false

        func hasConfirmedLogitechSensorDPI(_ dpi: Int) -> Bool {
            confirmedLogitechSensorDPI == dpi
        }

        var confirmedLogitechSensorDPI: Int?
        var confirmedLogitechHighResolutionWheel: Bool?
        var needsLogitechSensorDPIRestoreRetry = false
        var needsLogitechHighResolutionWheelRestoreRetry = false
        private(set) var actions = [String]()

        func applyConfiguredSensorDPI(_ dpi: Int) {
            actions.append("dpi:\(dpi)")
        }

        func applyConfiguredHighResolutionWheel(_ enabled: Bool) {
            actions.append("hiResWheel:\(enabled)")
        }

        func requestLogitechControlsForcedReconfiguration() {
            actions.append("controls")
        }

        func prepareSensorDPIForReconnect() {
            actions.append("prepareDPI")
        }

        func prepareHighResolutionWheelForReconnect() {
            actions.append("prepareHiResWheel")
        }

        func stopManagingSensorDPI() {
            actions.append("restoreDPI")
        }

        func stopManagingHighResolutionWheel() {
            actions.append("restoreHiResWheel")
        }

        func resetActions() {
            actions.removeAll()
        }
    }

    private func scheme(dpi: Int? = nil, highResolutionWheel: Bool? = nil) -> Scheme {
        var scheme = Scheme()
        scheme.pointer.hardwareDPI = dpi
        scheme.logitech.highResolutionWheel = highResolutionWheel
        return scheme
    }

    func testApplyOnlyUpdatesChangedSettings() {
        let device = Device()
        let reconciler = LogitechDeviceSettingsReconciler(device: device)

        reconciler.apply(scheme(dpi: 1000, highResolutionWheel: true))
        XCTAssertEqual(device.actions, ["dpi:1000", "hiResWheel:true"])

        device.resetActions()
        device.confirmedLogitechSensorDPI = 1000
        device.confirmedLogitechHighResolutionWheel = true
        reconciler.apply(scheme(dpi: 1000, highResolutionWheel: true))
        XCTAssertTrue(device.actions.isEmpty)

        reconciler.apply(scheme(dpi: 1000, highResolutionWheel: false))
        XCTAssertEqual(device.actions, ["hiResWheel:false"])
    }

    func testUnconfirmedUnchangedSettingsAreAppliedAgain() {
        let device = Device()
        let reconciler = LogitechDeviceSettingsReconciler(device: device)
        let settings = scheme(dpi: 1000, highResolutionWheel: true)

        reconciler.apply(settings)
        device.resetActions()

        // A requested value is not confirmation. This covers initial input,
        // reconnects, and the unknown state left by exhausted retries.
        reconciler.apply(settings)

        XCTAssertEqual(device.actions, ["dpi:1000", "hiResWheel:true"])
    }

    func testUnchangedSchemeDoesNotRestartPendingHardwareWork() {
        let device = Device()
        let reconciler = LogitechDeviceSettingsReconciler(device: device)
        let settings = scheme(dpi: 1000, highResolutionWheel: true)
        reconciler.apply(settings)
        device.isLogitechSensorDPIApplyRunning = true
        device.isLogitechHighResolutionWheelApplyRunning = true
        device.resetActions()
        reconciler.apply(settings)
        XCTAssertTrue(device.actions.isEmpty)

        reconciler.apply(scheme(dpi: 1200, highResolutionWheel: false))
        XCTAssertEqual(device.actions, ["dpi:1200", "hiResWheel:false"])
        device.resetActions()
        reconciler.apply(.init())
        XCTAssertEqual(device.actions, ["restoreDPI", "restoreHiResWheel"])
        device.resetActions()
        reconciler.apply(.init())
        XCTAssertTrue(device.actions.isEmpty)
    }

    func testNilTransitionRestoresOriginalHardwareSettings() {
        let device = Device()
        let reconciler = LogitechDeviceSettingsReconciler(device: device)

        reconciler.apply(scheme(dpi: 1000, highResolutionWheel: true))
        device.resetActions()
        reconciler.apply(scheme(dpi: nil, highResolutionWheel: nil))

        XCTAssertEqual(device.actions, ["restoreDPI", "restoreHiResWheel"])
    }

    func testReapplyForcesEveryVolatileSettingAndControlReconfiguration() {
        let device = Device()
        let reconciler = LogitechDeviceSettingsReconciler(device: device)
        let settings = scheme(dpi: 1200, highResolutionWheel: true)

        reconciler.apply(settings)
        device.resetActions()
        reconciler.reapply(settings)

        XCTAssertEqual(device.actions, [
            "prepareDPI",
            "prepareHiResWheel",
            "dpi:1200",
            "hiResWheel:true",
            "controls"
        ])
    }

    func testWakeReapplyKeepsSuspendedRuntimeStateUntilVerification() {
        let device = Device()
        let reconciler = LogitechDeviceSettingsReconciler(device: device)
        let settings = scheme(dpi: 1200, highResolutionWheel: true)

        reconciler.apply(settings)
        device.resetActions()
        reconciler.reapplyAfterWake(settings)

        XCTAssertEqual(device.actions, [
            "dpi:1200",
            "hiResWheel:true",
            "controls"
        ])
    }

    func testReapplyRetriesStoppingUnconfiguredWheelManagement() {
        let device = Device()
        let reconciler = LogitechDeviceSettingsReconciler(device: device)
        let settings = scheme(dpi: nil, highResolutionWheel: nil)

        reconciler.reapply(settings)

        XCTAssertEqual(device.actions, [
            "prepareDPI",
            "restoreDPI",
            "restoreHiResWheel",
            "controls"
        ])
    }

    func testSameNilSettingsRetryAnExhaustedDPIRestore() {
        let device = Device()
        device.needsLogitechSensorDPIRestoreRetry = true
        let reconciler = LogitechDeviceSettingsReconciler(device: device)

        reconciler.apply(scheme(dpi: nil, highResolutionWheel: nil))

        XCTAssertEqual(device.actions, ["restoreDPI"])
    }

    func testSameNilSettingsRetryAnExhaustedWheelRestore() {
        let device = Device()
        device.needsLogitechHighResolutionWheelRestoreRetry = true
        let reconciler = LogitechDeviceSettingsReconciler(device: device)

        reconciler.apply(scheme(dpi: nil, highResolutionWheel: nil))

        XCTAssertEqual(device.actions, ["restoreHiResWheel"])
    }

    func testRemovedDeviceIgnoresApplyAndReapply() {
        let device = Device()
        device.isRemoved = true
        let reconciler = LogitechDeviceSettingsReconciler(device: device)

        reconciler.apply(scheme(dpi: 1000, highResolutionWheel: true))
        reconciler.reapply(scheme(dpi: 1000, highResolutionWheel: true))

        XCTAssertTrue(device.actions.isEmpty)
    }
}
