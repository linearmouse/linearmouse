// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

@testable import KeyKit
import XCTest

final class KeyKitTests: XCTestCase {
    func testPostSymbolicHotKey() throws {
        try postSymbolicHotKey(.spaceLeft)
    }

    func testPostSystemDefinedKey() throws {
        postSystemDefinedKey(.soundDown)
    }
}
