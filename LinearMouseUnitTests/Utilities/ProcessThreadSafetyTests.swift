// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Darwin
@testable import LinearMouse
import XCTest

final class ProcessThreadSafetyTests: XCTestCase {
    func testCurrentProcessMetadataCanBeReadOffMainThread() {
        let expectation = expectation(description: "Read process metadata off the main thread")

        DispatchQueue.global(qos: .userInitiated).async {
            let currentPid = getpid()

            XCTAssertFalse((currentPid.processPath ?? "").isEmpty)
            XCTAssertFalse((currentPid.processName ?? "").isEmpty)
            _ = currentPid.bundleIdentifier

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
    }
}
