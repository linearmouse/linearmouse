// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PointerSchemeApplicationTests: XCTestCase {
    private final class Application {
        let state = PointerSchemeApplicationState()

        @discardableResult
        func apply(_ pointer: Scheme.Pointer, to target: PointerSettingsTarget) -> Bool {
            state.apply(Scheme(pointer: pointer), to: target)
        }

        func invalidate() {
            state.invalidate()
        }
    }

    private final class Target: PointerSettingsTarget {
        var supportsLinearPointerScaling = true
        var actions = [String]()
        var failingAction: String?
        var readSystemAcceleration: (() -> Double?)?

        private func write(_ action: String) -> Bool {
            actions.append(action)
            return action != failingAction
        }

        func setDisablePointerAcceleration(_ value: Bool) -> Bool {
            write("linear:\(value)")
        }

        func setPointerSpeed(_ value: Double) -> Bool {
            write("speed:\(value)")
        }

        func setPointerAcceleration(_ value: Double) -> Bool {
            write("acceleration:\(value)")
        }

        func restorePointerSpeed() -> Bool {
            write("restoreSpeed")
        }

        func restorePointerAcceleration() -> Bool {
            if let readSystemAcceleration {
                return PointerAccelerationRestoreOperation.perform(
                    fallback: 0.6875,
                    readSystemValue: readSystemAcceleration,
                    write: setPointerAcceleration
                )
            }
            return write("restoreAcceleration")
        }
    }

    func testSpeedFailureStillAppliesOrRestoresAcceleration() {
        for restoresDefaults in [false, true] {
            let target = Target()
            let application = Application()
            var pointer = Scheme.Pointer()
            if !restoresDefaults {
                pointer.speed = .value(0.5)
                pointer.acceleration = .value(2)
            }
            target.failingAction = restoresDefaults ? "restoreSpeed" : "speed:0.5"
            XCTAssertFalse(application.apply(pointer, to: target))
            XCTAssertEqual(
                target.actions,
                restoresDefaults
                    ? ["linear:false", "restoreSpeed", "restoreAcceleration"]
                    : ["linear:false", "speed:0.5", "acceleration:2.0"]
            )
            XCTAssertNil(application.state.snapshot)

            target.failingAction = nil
            XCTAssertTrue(application.apply(pointer, to: target))
            target.actions.removeAll()
            XCTAssertTrue(application.apply(pointer, to: target))
            XCTAssertTrue(target.actions.isEmpty)
        }
    }

    func testSystemReadFailureWritesFallbackAndRetriesUntilActualValueIsRestored() {
        let target = Target()
        let application = Application()
        var reads = 0
        target.readSystemAcceleration = {
            reads += 1
            return reads == 1 ? nil : 1.5
        }
        XCTAssertFalse(application.apply(.init(), to: target))
        XCTAssertEqual(target.actions.last, "acceleration:0.6875")
        XCTAssertNil(application.state.snapshot)

        target.actions.removeAll()
        XCTAssertTrue(application.apply(.init(), to: target))
        XCTAssertEqual(target.actions.last, "acceleration:1.5")
        XCTAssertEqual(reads, 2)
        target.actions.removeAll()
        XCTAssertTrue(application.apply(.init(), to: target))
        XCTAssertTrue(target.actions.isEmpty)
        XCTAssertEqual(reads, 2)
    }

    func testSuccessfulSystemReadWithFailedWriteStillRequiresRetry() {
        let target = Target()
        let application = Application()
        target.readSystemAcceleration = { 1.5 }
        target.failingAction = "acceleration:1.5"
        XCTAssertFalse(application.apply(.init(), to: target))
        XCTAssertNil(application.state.snapshot)
        target.failingAction = nil
        XCTAssertTrue(application.apply(.init(), to: target))
        XCTAssertNotNil(application.state.snapshot)
    }

    func testFailedWritesAreRetriedWithoutRecordingSnapshot() {
        for action in ["linear:false", "restoreSpeed", "restoreAcceleration", "speed:0.5", "acceleration:2.0"] {
            let target = Target()
            let application = Application()
            var pointer = Scheme.Pointer()
            if action == "speed:0.5" {
                pointer.speed = .value(0.5)
            }
            if action == "acceleration:2.0" {
                pointer.acceleration = .value(2)
            }
            target.failingAction = action
            XCTAssertFalse(application.apply(pointer, to: target), action)
            XCTAssertNil(application.state.snapshot)
            target.failingAction = nil
            target.actions.removeAll()
            XCTAssertTrue(application.apply(pointer, to: target))
            XCTAssertTrue(target.actions.contains(action))
            target.actions.removeAll()
            XCTAssertTrue(application.apply(pointer, to: target))
            XCTAssertTrue(target.actions.isEmpty)
        }
    }

    func testPartialFailureThenReturningToOldSchemeStillReapplies() {
        let target = Target()
        let application = Application()
        var old = Scheme.Pointer()
        old.speed = .value(0.25)
        old.acceleration = .value(1)
        XCTAssertTrue(application.apply(old, to: target))
        var next = old
        next.speed = .value(0.75)
        next.acceleration = .value(2)
        target.failingAction = "acceleration:2.0"
        XCTAssertFalse(application.apply(next, to: target))
        target.actions.removeAll()
        target.failingAction = nil
        XCTAssertTrue(application.apply(old, to: target))
        XCTAssertEqual(target.actions, ["linear:false", "speed:0.25", "acceleration:1.0"])
    }

    func testEquivalentSchemesPerformNoIO() {
        let target = Target()
        let reconciler = Application()
        var pointer = Scheme.Pointer()
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["linear:false", "restoreSpeed", "restoreAcceleration"])
        target.actions.removeAll()

        pointer.speed = .unset
        pointer.acceleration = .unset
        pointer.disableAcceleration = false
        pointer.redirectsToScroll = true
        reconciler.apply(pointer, to: target)
        XCTAssertTrue(target.actions.isEmpty)
    }

    func testOnlyChangedPropertiesAreAppliedWithResolutionDependency() {
        let target = Target()
        let reconciler = Application()
        var pointer = Scheme.Pointer()
        pointer.speed = .value(0.5)
        pointer.acceleration = .value(1)
        reconciler.apply(pointer, to: target)
        target.actions.removeAll()
        reconciler.apply(pointer, to: target)
        XCTAssertTrue(target.actions.isEmpty)

        pointer.acceleration = .value(2)
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["acceleration:2.0"])
        target.actions.removeAll()
        pointer.speed = .value(0.75)
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["speed:0.75", "acceleration:2.0"])
        target.actions.removeAll()
        pointer.speed = nil
        pointer.acceleration = nil
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["restoreSpeed", "restoreAcceleration"])
        target.actions.removeAll()
        reconciler.apply(pointer, to: target)
        XCTAssertTrue(target.actions.isEmpty)
    }

    func testDisabledAccelerationPreservesSpeedAndReappliesTrackingSpeedOnModeChange() {
        let target = Target()
        let reconciler = Application()
        var pointer = Scheme.Pointer()
        reconciler.apply(pointer, to: target)
        target.actions.removeAll()
        pointer.disableAcceleration = true
        pointer.speed = .value(0.75)
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["linear:true", "restoreAcceleration"])
        target.actions.removeAll()
        reconciler.apply(pointer, to: target)
        XCTAssertTrue(target.actions.isEmpty)
        pointer.disableAcceleration = false
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["linear:false", "speed:0.75", "restoreAcceleration"])
    }

    func testLegacyDisabledAccelerationIgnoresSpeedAndAccelerationChanges() {
        let target = Target()
        target.supportsLinearPointerScaling = false
        let reconciler = Application()
        var pointer = Scheme.Pointer()
        pointer.disableAcceleration = true
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["acceleration:-1.0"])
        target.actions.removeAll()
        pointer.acceleration = .value(2)
        pointer.speed = .value(0.5)
        reconciler.apply(pointer, to: target)
        XCTAssertTrue(target.actions.isEmpty)
        pointer.disableAcceleration = false
        reconciler.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["speed:0.5", "acceleration:2.0"])
    }

    func testSpeedChangedWhileDisabledIsAppliedWhenReenabled() {
        let target = Target()
        let application = Application()
        var pointer = Scheme.Pointer()
        pointer.speed = .value(0.25)
        application.apply(pointer, to: target)
        pointer.disableAcceleration = true
        application.apply(pointer, to: target)
        pointer.speed = .value(0.75)
        application.apply(pointer, to: target)
        target.actions.removeAll()
        pointer.disableAcceleration = false
        application.apply(pointer, to: target)
        XCTAssertEqual(target.actions, ["linear:false", "speed:0.75", "restoreAcceleration"])
    }

    func testInvalidationReappliesSettingsAndDevicesHaveIndependentCaches() {
        let target = Target()
        let reconciler = Application()
        reconciler.apply(.init(), to: target)
        let initialActions = target.actions
        target.actions.removeAll()
        reconciler.invalidate()
        reconciler.apply(.init(), to: target)
        XCTAssertEqual(target.actions, initialActions)

        let otherTarget = Target()
        Application().apply(.init(), to: otherTarget)
        XCTAssertEqual(otherTarget.actions, initialActions)
    }
}
