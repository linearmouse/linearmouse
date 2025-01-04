// MIT License
// Copyright (c) 2021-2025 LinearMouse

@testable import LinearMouse
import XCTest

class ModifierActionsTransformerTests: XCTestCase {
    func testModifierActions() throws {
        var event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 2, wheel3: 0)!
        let modifiers = Scheme.Scrolling.Modifiers(command: .auto,
                                                   shift: .alterOrientation,
                                                   option: .changeSpeed(scale: 2),
                                                   control: .changeSpeed(scale: 3))
        let transformer = ModifierActionsTransformer(modifiers: .init(vertical: modifiers, horizontal: modifiers))
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
