// MIT License
// Copyright (c) 2021-2024 LinearMouse

@testable import KeyKit
import XCTest

final class KeyKitTests: XCTestCase {
    func testPressKey() throws {
        let keySimulator = KeySimulator()
        try keySimulator.press(.home)
    }

    func testPostSymbolicHotKey() throws {
        try postSymbolicHotKey(.spaceLeft)
    }

    func testPostSystemDefinedKey() throws {
        postSystemDefinedKey(.soundDown)
    }
}
