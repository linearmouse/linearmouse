// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import KeyKit
import XCTest

final class KeyKitTests: XCTestCase {
    /// The tests below post real keyboard / system-defined events into the OS, which causes
    /// observable side effects (volume change, Mission Control space switch, stuck modifier
    /// state in WindowServer, etc.). Gate them behind an env var so day-to-day `swift test`
    /// stays side-effect free; CI can opt in by setting `RUN_INTEGRATION_TESTS=1`.
    private func skipUnlessIntegrationEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run KeyKit integration tests that post real system events."
        )
    }

    func testKeySimulatorInitializesOffMainThread() {
        let expectation = expectation(description: "Initialize KeySimulator off the main thread")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = KeySimulator()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
    }

    func testPressKey() throws {
        try skipUnlessIntegrationEnabled()
        let keySimulator = KeySimulator()
        try keySimulator.press(.home)
    }

    func testPostSymbolicHotKey() throws {
        try skipUnlessIntegrationEnabled()
        try postSymbolicHotKey(.spaceLeft)
    }

    func testPostSystemDefinedKey() throws {
        try skipUnlessIntegrationEnabled()
        postSystemDefinedKey(.soundDown)
    }
}
