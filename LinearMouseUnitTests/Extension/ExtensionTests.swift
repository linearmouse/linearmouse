//
//  ExtensionTests.swift
//  LinearMouseUnitTests
//
//  Created by Jiahao Lu on 2022/1/4.
//

import XCTest
@testable import LinearMouse

class ExtensionTests: XCTestCase {
    func testInfiniteLoopExtension() throws {
        var thrownError: Error?
        XCTAssertThrowsError(try Extension(name: "Extension", script: "for(;;);")) {
            thrownError = $0
        }
        XCTAssertTrue(
            thrownError is ExtensionError,
            "Unexpected error type: \(type(of: thrownError))"
        )
    }
}
