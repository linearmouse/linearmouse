//
//  ModifierActionsTests.swift
//  LinearMouseUnitTests
//
//  Created by lujjjh on 2021/11/24.
//

import XCTest
@testable import LinearMouse

class ModifierActionsTests: XCTestCase {
    func testModifierActions() throws {
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        let transformer = ModifierActions(commandAction: .init(type: .noAction, speedFactor: 0),
                                          shiftAction: .init(type: .alterOrientation, speedFactor: 0),
                                          alternateAction: .init(type: .changeSpeed, speedFactor: 2),
                                          controlAction: .init(type: .changeSpeed, speedFactor: 3))
        event.flags.insert(.maskCommand)
        event.flags.insert(.maskShift)
        event.flags.insert(.maskAlternate)
        event.flags.insert(.maskControl)
        event = transformer.transform(event)!
        var view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 6)
        XCTAssertEqual(view.deltaY, 12)

        event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        event.flags.insert(.maskCommand)
        event.flags.insert(.maskShift)
        event.flags.insert(.maskAlternate)
        event = transformer.transform(event)!
        view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, 4)
    }
}
