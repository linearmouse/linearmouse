//
//  OrientNormalizerTests.swift
//  LinearMouseUnitTests
//
//  Created by lujjjh on 2021/11/20.
//

import XCTest
@testable import LinearMouse

class OrientNormalizerTests: XCTestCase {
    func testEnabledPositive() throws {
        let transformer = OrientNormalizer(enabled: true)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 42, wheel3: 0)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 42)
        XCTAssertEqual(view.deltaY, 0)
        event = transformer.transform(event)!
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 42)
        event = transformer.transform(event)!
        XCTAssertEqual(view.deltaX, 42)
        XCTAssertEqual(view.deltaY, 0)
    }

    func testEnabledNegative() throws {
        let transformer = OrientNormalizer(enabled: true)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 42, wheel2: 0, wheel3: 0)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 42)
        event = transformer.transform(event)!
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 42)
        event = transformer.transform(event)!
        XCTAssertEqual(view.deltaX, 0)
        XCTAssertEqual(view.deltaY, 42)
    }

    func testDisabled() throws {
        let transformer = OrientNormalizer(enabled: false)
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 42, wheel3: 0)!
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 42)
        XCTAssertEqual(view.deltaY, 0)
        event = transformer.transform(event)!
        XCTAssertEqual(view.deltaX, 42)
        XCTAssertEqual(view.deltaY, 0)
        event = transformer.transform(event)!
        XCTAssertEqual(view.deltaX, 42)
        XCTAssertEqual(view.deltaY, 0)
    }
}
