//
//  RuntimeCoreTests.swift
//  LinearMouseUnitTests
//
//  Created by Jiahao Lu on 2022/1/6.
//

import XCTest
import JavaScriptCore
@testable import LinearMouse

class CoreTests: XCTestCase {
    func testAppVersion() throws {
        let context = JSContext()!
        Core().registerInContext(context)
        XCTAssertEqual(context.evaluateScript("__APP_VERSION__").toString(), LinearMouse.appVersion)
        context.evaluateScript("__APP_VERSION__ = '';")
        XCTAssertEqual(context.evaluateScript("__APP_VERSION__").toString(), LinearMouse.appVersion)
    }
}
