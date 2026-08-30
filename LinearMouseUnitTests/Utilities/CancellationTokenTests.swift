// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class CancellationTokenTests: XCTestCase {
    func testSourceCancelsExistingToken() {
        let source = CancellationSource()
        let token = source.token

        XCTAssertTrue(token.shouldContinue)
        source.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    func testSourcesHaveIndependentLifetimes() {
        let first = CancellationSource()
        let second = CancellationSource()

        first.cancel()

        XCTAssertTrue(first.token.isCancelled)
        XCTAssertFalse(second.token.isCancelled)
    }
}
