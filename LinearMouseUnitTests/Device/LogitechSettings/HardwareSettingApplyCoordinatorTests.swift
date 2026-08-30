// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// Covers the shared retry and confirmation policy used by volatile Logitech settings.
final class HardwareSettingApplyCoordinatorTests: XCTestCase {
    private final class Scheduler {
        struct ScheduledWork {
            let delay: TimeInterval
            let work: () -> Void
        }

        private(set) var work = [ScheduledWork]()

        func schedule(delay: TimeInterval, work: @escaping () -> Void) {
            self.work.append(.init(delay: delay, work: work))
        }

        func runNext() {
            work.removeFirst().work()
        }
    }

    func testRetriesFailedApplyThenConfirmsSuccessfulApply() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1, 2],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var results = [false, true, true]
        var attempts = [HardwareSettingApplyCoordinator.Attempt]()

        coordinator.start { attempt in
            attempts.append(attempt)
            return results.removeFirst()
        }

        XCTAssertEqual(scheduler.work.map(\.delay), [0])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [1])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [3])
        scheduler.runNext()

        XCTAssertTrue(scheduler.work.isEmpty)
        XCTAssertEqual(attempts, [
            .init(verifiesCachedValue: false, number: 1, isFinal: false),
            .init(verifiesCachedValue: false, number: 2, isFinal: false),
            .init(verifiesCachedValue: true, number: 1, isFinal: false)
        ])
    }

    func testRetriesFailedConfirmationWithoutRestartingApplyPhase() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1, 2],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var results = [true, false, true]
        var verificationFlags = [Bool]()

        coordinator.start { attempt in
            verificationFlags.append(attempt.verifiesCachedValue)
            return results.removeFirst()
        }

        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [3])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [1])
        scheduler.runNext()

        XCTAssertTrue(scheduler.work.isEmpty)
        XCTAssertEqual(verificationFlags, [false, true, true])
    }

    func testStopsAfterRetryBudgetIsExhausted() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1, 2],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var calls = 0
        var attempts = [HardwareSettingApplyCoordinator.Attempt]()

        coordinator.start { attempt in
            attempts.append(attempt)
            calls += 1
            return false
        }

        XCTAssertEqual(scheduler.work.map(\.delay), [0])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [1])
        scheduler.runNext()
        XCTAssertEqual(scheduler.work.map(\.delay), [2])
        scheduler.runNext()

        XCTAssertEqual(calls, 3)
        XCTAssertEqual(attempts.last, .init(verifiesCachedValue: false, number: 3, isFinal: true))
        XCTAssertTrue(scheduler.work.isEmpty)
    }

    func testNewRequestCancelsPreviouslyScheduledWork() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var firstRequestCalls = 0
        var secondRequestCalls = 0

        coordinator.start { _ in
            firstRequestCalls += 1
            return true
        }
        coordinator.start { _ in
            secondRequestCalls += 1
            return true
        }

        scheduler.runNext()
        scheduler.runNext()

        XCTAssertEqual(firstRequestCalls, 0)
        XCTAssertEqual(secondRequestCalls, 1)
        XCTAssertEqual(scheduler.work.map(\.delay), [3])
    }

    func testCancelPreventsScheduledWorkFromRunning() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var calls = 0

        coordinator.start { _ in
            calls += 1
            return true
        }
        coordinator.cancel()
        scheduler.runNext()

        XCTAssertEqual(calls, 0)
        XCTAssertTrue(scheduler.work.isEmpty)
    }

    func testRunningAttemptObservesWhenItIsSuperseded() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var firstAttemptShouldContinue: (() -> Bool)?

        coordinator.start { attempt in
            firstAttemptShouldContinue = attempt.shouldContinue
            coordinator.start { _ in true }
            return false
        }
        scheduler.runNext()

        XCTAssertEqual(firstAttemptShouldContinue?(), false)
        XCTAssertEqual(scheduler.work.map(\.delay), [0])
    }

    func testReportsFailureAfterRetryBudgetIsExhausted() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var completions = [Bool]()

        coordinator.start { _ in
            false
        } completion: {
            completions.append($0)
        }
        scheduler.runNext()
        scheduler.runNext()

        XCTAssertEqual(completions, [false])
    }

    func testConfirmationRetriesAfterFirmwareResetsAnInitiallySuccessfulWrite() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1, 2],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var hardwareEnabled = false
        var confirmationCount = 0
        var completions = [Bool]()

        coordinator.start { attempt in
            if !attempt.verifiesCachedValue {
                hardwareEnabled = true
                return true
            }

            confirmationCount += 1
            if confirmationCount == 1 {
                // Firmware finished waking and discarded the first write.
                hardwareEnabled = false
                hardwareEnabled = true // Rewrite, then require a fresh read.
                return false
            }
            return hardwareEnabled
        } completion: {
            completions.append($0)
        }

        scheduler.runNext() // Initial write.
        scheduler.runNext() // First confirmation sees the reset and rewrites.
        scheduler.runNext() // Retry confirmation reads the rewritten mode.

        XCTAssertEqual(confirmationCount, 2)
        XCTAssertEqual(completions, [true])
    }

    func testHiResEnableRetriesUntilMultiplierIsAvailableAndThenConfirmsFromCache() {
        let scheduler = Scheduler()
        let coordinator = HardwareSettingApplyCoordinator(
            retryDelays: [1],
            confirmationDelay: 3,
            scheduler: scheduler.schedule
        )
        var capabilityResponses: [Int?] = [nil, 8]
        var capabilityReads = 0
        var modeSetCalls = 0
        var cachedMultiplier: Int?
        var completions = [Bool]()

        coordinator.start { attempt in
            guard let multiplier = LogitechHiResEnabledMultiplier.resolve(
                cached: cachedMultiplier,
                load: {
                    capabilityReads += 1
                    return capabilityResponses.removeFirst()
                }
            ) else {
                return false
            }

            cachedMultiplier = multiplier
            if !attempt.verifiesCachedValue {
                // The mode/set path is otherwise healthy; only the first
                // capabilities read prevents the initial apply from settling.
                modeSetCalls += 1
            }
            return true
        } completion: {
            completions.append($0)
        }

        scheduler.runNext() // Capabilities unavailable; schedule apply retry.
        XCTAssertEqual(scheduler.work.map(\.delay), [1])
        scheduler.runNext() // Capabilities and mode/set succeed.
        XCTAssertEqual(scheduler.work.map(\.delay), [3])
        scheduler.runNext() // Confirmation reuses the cached multiplier.

        XCTAssertEqual(capabilityReads, 2)
        XCTAssertEqual(modeSetCalls, 1)
        XCTAssertEqual(cachedMultiplier, 8)
        XCTAssertEqual(completions, [true])
        XCTAssertTrue(scheduler.work.isEmpty)
    }

    func testHiResMultiplierOneIsValidAndReusable() {
        var loads = 0
        let loaded = LogitechHiResEnabledMultiplier.resolve(cached: nil) {
            loads += 1
            return 1
        }
        let cached = LogitechHiResEnabledMultiplier.resolve(cached: loaded) {
            loads += 1
            return nil
        }

        XCTAssertEqual(loaded, 1)
        XCTAssertEqual(cached, 1)
        XCTAssertEqual(loads, 1)
    }
}
