// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ExponentialBackoffTests: XCTestCase {
    func testDelayGrowsUntilMaximum() {
        var backoff = ExponentialBackoff(initialDelay: 0.5, maximumDelay: 4)

        XCTAssertEqual(
            (0 ..< 6).map { _ in backoff.nextDelay() },
            [0.5, 1, 2, 4, 4, 4]
        )
    }

    func testResetRestoresInitialDelay() {
        var backoff = ExponentialBackoff(initialDelay: 2, maximumDelay: 60)
        _ = backoff.nextDelay()
        _ = backoff.nextDelay()

        backoff.reset()

        XCTAssertEqual(backoff.nextDelay(), 2)
    }
}
