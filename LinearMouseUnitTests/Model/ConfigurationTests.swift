// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

@testable import LinearMouse
import XCTest

class ConfigurationTests: XCTestCase {
    func testDump() throws {
        print(try Configuration(schemes: []).dump())
    }
}
