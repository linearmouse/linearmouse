// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class FrontmostApplicationTrackerTests: XCTestCase {
    func testSnapshotCanBeReadOffMainThreadAfterMainThreadPrime() {
        let primed = expectation(description: "Tracker primed on main thread")
        DispatchQueue.main.async {
            FrontmostApplicationTracker.shared.prime()
            primed.fulfill()
        }
        wait(for: [primed], timeout: 5)

        let readSnapshot = expectation(description: "Read tracker snapshot off the main thread")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = FrontmostApplicationTracker.shared.processIdentifier
            _ = FrontmostApplicationTracker.shared.bundleIdentifier
            readSnapshot.fulfill()
        }

        wait(for: [readSnapshot], timeout: 5)
    }
}
