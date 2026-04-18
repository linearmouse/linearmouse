// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class FrontmostApplicationTrackerTests: XCTestCase {
    func testSnapshotCanBeReadOffMainThreadAfterMainThreadStart() {
        let started = expectation(description: "Tracker started on main thread")
        DispatchQueue.main.async {
            FrontmostApplicationTracker.shared.start()
            started.fulfill()
        }
        wait(for: [started], timeout: 5)

        let readSnapshot = expectation(description: "Read tracker snapshot off the main thread")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = FrontmostApplicationTracker.shared.processIdentifier
            _ = FrontmostApplicationTracker.shared.bundleIdentifier
            readSnapshot.fulfill()
        }

        wait(for: [readSnapshot], timeout: 5)
    }
}
