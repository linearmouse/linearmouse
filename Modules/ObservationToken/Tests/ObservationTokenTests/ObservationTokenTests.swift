// MIT License
// Copyright (c) 2021-2024 LinearMouse

@testable import ObservationToken
import XCTest

final class ObservationTokenTests: XCTestCase {
    func testCancel() throws {
        var cancelled = false

        do {
            ObservationToken {
                cancelled = true
            }
        }

        XCTAssertTrue(cancelled)
    }

    func testTieToLifetime() throws {
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
