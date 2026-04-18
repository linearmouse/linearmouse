// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import KeyKit
import XCTest

final class KeyKitTests: XCTestCase {
    func testKeySimulatorInitializesOffMainThread() {
        let expectation = expectation(description: "Initialize KeySimulator off the main thread")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = KeySimulator()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
    }

    func testPressKey() throws {
        let keySimulator = KeySimulator()
        try keySimulator.press(.home)
    }

    func testPostSymbolicHotKey() throws {
        try postSymbolicHotKey(.spaceLeft)
    }

    func testPostSystemDefinedKey() {
        postSystemDefinedKey(.soundDown)
    }
}
