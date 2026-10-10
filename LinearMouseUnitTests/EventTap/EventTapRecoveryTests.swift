// MIT License
// Copyright (c) 2021-2026 LinearMouse

import IOKit.hidsystem
@testable import LinearMouse
import XCTest

final class EventTapRecoveryTests: XCTestCase {
    func testStalePreflightGrantDoesNotHideRevocation() {
        for state in [kIOHIDAccessTypeDenied, kIOHIDAccessTypeUnknown] {
            XCTAssertFalse(AccessibilityPermission.Snapshot(
                accessibility: true, postEvent: true, hidPostEvent: state
            )
            .enabled)
        }
        XCTAssertFalse(AccessibilityPermission.Snapshot(
            accessibility: false, postEvent: true, hidPostEvent: kIOHIDAccessTypeGranted
        )
        .enabled)
        // A cached CG denial must not override a current IOHID grant.
        XCTAssertTrue(AccessibilityPermission.Snapshot(
            accessibility: true, postEvent: false, hidPostEvent: kIOHIDAccessTypeGranted
        )
        .enabled)
    }

    func testFailuresHaveFiniteRetryBudgetAndOnlyOneNotification() {
        var scheduled: [() -> Void] = []
        var attempts = 0
        var failures = 0
        let recovery = EventTapRecovery(
            schedule: { _, work in scheduled.append(work) },
            attempt: { completion in
                attempts += 1
                completion(.failed)
            },
            onFailure: { _ in failures += 1 }
        )
        recovery.start()
        recovery.start()
        while !scheduled.isEmpty {
            scheduled.removeFirst()()
        }
        recovery.start()
        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(failures, 1)
    }

    func testStopCancelsScheduledRetryAndAllowsFreshStart() {
        var scheduled: [() -> Void] = []
        var attempts = 0
        let recovery = EventTapRecovery(
            schedule: { _, work in scheduled.append(work) },
            attempt: { completion in
                attempts += 1
                completion(.failed)
            },
            onFailure: { _ in XCTFail("Cancelled attempt must not report failure") }
        )
        recovery.start()
        recovery.stop()
        recovery.start()
        scheduled.removeFirst()()
        XCTAssertEqual(attempts, 2)
        recovery.stop()
        scheduled.removeFirst()()
        XCTAssertEqual(attempts, 2)
    }

    func testLateResultAfterStopIsIgnored() {
        var completions: [(EventTapRecovery.StartResult) -> Void] = []
        let recovery = EventTapRecovery(
            schedule: { _, _ in XCTFail("Must not retry") },
            attempt: {
                completions.append($0)
            },
            onFailure: { _ in XCTFail("Must not show stale error") }
        )
        recovery.start()
        recovery.stop()
        recovery.start()
        completions[0](.permissionRequired)
        completions[1](.started)
    }

    func testSuccessStopsRetries() {
        var work: (() -> Void)?
        var attempts = 0
        let recovery = EventTapRecovery(
            schedule: { _, retry in work = retry },
            attempt: { completion in
                attempts += 1
                completion(attempts == 1 ? .failed : .started)
            },
            onFailure: { _ in XCTFail("Recovered successfully") }
        )
        recovery.start()
        work?()
        recovery.start()
        XCTAssertEqual(attempts, 2)
    }

    func testMissingPermissionShowsRecoveryWithoutCreatingRetryLoop() {
        var failures = 0
        let recovery = EventTapRecovery(
            schedule: { _, _ in XCTFail("Must not retry denied permission") },
            attempt: {
                $0(.permissionRequired)
            },
            onFailure: { _ in failures += 1 }
        )
        recovery.start()
        recovery.start()
        XCTAssertEqual(failures, 1)
    }
}
