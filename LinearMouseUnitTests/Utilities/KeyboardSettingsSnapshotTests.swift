// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class KeyboardSettingsSnapshotTests: XCTestCase {
    func testKeyRepeatTimingCanBeReadOffMainThreadAfterMainThreadRefresh() {
        let refreshed = expectation(description: "Refresh key repeat timing on main thread")
        DispatchQueue.main.async {
            KeyboardSettingsSnapshot.shared.refresh()
            refreshed.fulfill()
        }
        wait(for: [refreshed], timeout: 5)

        let readSnapshot = expectation(description: "Read key repeat timing off the main thread")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = KeyboardSettingsSnapshot.shared.keyRepeatDelay
            _ = KeyboardSettingsSnapshot.shared.keyRepeatInterval
            readSnapshot.fulfill()
        }

        wait(for: [readSnapshot], timeout: 5)
    }
}
