// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import ObservationToken
import XCTest

final class ObservationTokenTests: XCTestCase {
    func testCancel() {
        var cancelled = false

        do {
            ObservationToken {
                cancelled = true
            }
        }

        XCTAssertTrue(cancelled)
    }

    func testTieToLifetime() {
        var cancelled = false

        class A {}

        do {
            let a = A()

            do {
                ObservationToken {
                    cancelled = true
                }.tieToLifetime(of: a)
            }

            XCTAssertFalse(cancelled)
        }

        XCTAssertTrue(cancelled)
    }
}
