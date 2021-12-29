//
//  RuntimeConsoleTests.swift
//  LinearMouseUnitTests
//
//  Created by Jiahao Lu on 2022/1/6.
//

import XCTest
@testable import LinearMouse

class MemoryLogger: Logger {
    struct Entry: Equatable {
        var logLevel: LogLevel
        var message: String
    }

    var data: [Entry] = []

    func logger(logLevel: LogLevel, message: String) {
        data.append(.init(logLevel: logLevel, message: message))
    }
}

class ConsoleTests: XCTestCase {
    func testConsoleLog() throws {
        let context = JSContext()!
        let logger = MemoryLogger()
        Console(logger: logger).registerInContext(context)
        context.evaluateScript(#"""
            console.log('foo','bar');
            console.info(42);
            console.warn({ foo: 'bar' });
            console.error([2, 3, 5, 7]);
        """#)
        XCTAssertNil(context.exception)
        XCTAssertEqual(logger.data, [
            .init(logLevel: .log, message: "foo bar"),
            .init(logLevel: .info, message: "42"),
            // TODO: generic JavaScript object formatting
            .init(logLevel: .warn, message: "[object Object]"),
            .init(logLevel: .error, message: "2,3,5,7"),
        ])
    }
}
