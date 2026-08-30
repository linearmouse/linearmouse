// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class BoundedCleanupRequestTests: XCTestCase {
    func testNormalCompletionWinsExactlyOnce() throws {
        let scheduler = TestDeadlineScheduler()
        var outcomes = [BoundedCleanupRequest.Outcome]()
        var timeoutCount = 0
        let request = BoundedCleanupRequest(
            scheduler: scheduler.schedule,
            delivery: { $0() },
            onTimeout: { timeoutCount += 1 },
            completion: { outcomes.append($0) }
        )

        request.complete()
        request.complete()
        try scheduler.fire()

        XCTAssertFalse(request.authorizationToken.shouldContinue)
        XCTAssertEqual(outcomes, [.completed])
        XCTAssertEqual(timeoutCount, 0)
    }

    func testDeadlineWinsExactlyOnceAndRunsTimeoutHookFirst() throws {
        let scheduler = TestDeadlineScheduler()
        var events = [String]()
        let request = BoundedCleanupRequest(
            scheduler: scheduler.schedule,
            delivery: { $0() },
            onTimeout: { events.append("timeout") },
            completion: { outcome in events.append(String(describing: outcome)) }
        )

        try scheduler.fire()
        request.complete()

        XCTAssertFalse(request.authorizationToken.shouldContinue)
        XCTAssertEqual(events, ["timeout", "timedOut"])
    }

    func testDeadlineRevokesAuthorizationBeforeDelivery() throws {
        let scheduler = TestDeadlineScheduler()
        var deliveredAction: (() -> Void)?
        var outcomes = [BoundedCleanupRequest.Outcome]()
        let request = BoundedCleanupRequest(
            scheduler: scheduler.schedule,
            delivery: { deliveredAction = $0 },
            completion: { outcomes.append($0) }
        )

        XCTAssertTrue(request.authorizationToken.shouldContinue)

        try scheduler.fire()

        XCTAssertFalse(request.authorizationToken.shouldContinue)
        XCTAssertTrue(outcomes.isEmpty)

        try XCTUnwrap(deliveredAction)()
        XCTAssertEqual(outcomes, [.timedOut])
    }

    func testNormalCompletionRevokesAuthorizationBeforeDelivery() throws {
        let scheduler = TestDeadlineScheduler()
        var deliveredAction: (() -> Void)?
        var outcomes = [BoundedCleanupRequest.Outcome]()
        let request = BoundedCleanupRequest(
            scheduler: scheduler.schedule,
            delivery: { deliveredAction = $0 },
            completion: { outcomes.append($0) }
        )

        request.complete()

        XCTAssertFalse(request.authorizationToken.shouldContinue)
        XCTAssertTrue(outcomes.isEmpty)

        try XCTUnwrap(deliveredAction)()
        XCTAssertEqual(outcomes, [.completed])
    }

    func testNormalCompletionAndDeadlineRaceExactlyOnce() throws {
        for _ in 0 ..< 100 {
            let scheduler = TestDeadlineScheduler()
            let lock = NSLock()
            var outcomes = [BoundedCleanupRequest.Outcome]()
            var timeoutCount = 0
            let request = BoundedCleanupRequest(
                scheduler: scheduler.schedule,
                delivery: { $0() },
                onTimeout: {
                    lock.withLock { timeoutCount += 1 }
                },
                completion: { outcome in
                    lock.withLock { outcomes.append(outcome) }
                }
            )
            let deadline = try XCTUnwrap(scheduler.action)

            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    request.complete()
                } else {
                    deadline()
                }
            }

            let result = lock.withLock { (outcomes, timeoutCount) }
            XCTAssertFalse(request.authorizationToken.shouldContinue)
            XCTAssertEqual(result.0.count, 1)
            XCTAssertEqual(result.1, result.0 == [.timedOut] ? 1 : 0)
        }
    }

    func testSchedulerReceivesDefaultHardDeadline() {
        let scheduler = TestDeadlineScheduler()
        _ = BoundedCleanupRequest(
            scheduler: scheduler.schedule,
            delivery: { $0() },
            completion: { _ in }
        )

        XCTAssertEqual(scheduler.timeout, BoundedCleanupRequest.defaultTimeout)
    }
}

private final class TestDeadlineScheduler {
    private(set) var timeout: TimeInterval?
    private(set) var action: (() -> Void)?

    func schedule(timeout: TimeInterval, action: @escaping () -> Void) {
        self.timeout = timeout
        self.action = action
    }

    func fire() throws {
        try XCTUnwrap(action)()
    }
}
