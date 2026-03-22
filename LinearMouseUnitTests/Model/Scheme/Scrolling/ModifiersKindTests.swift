// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ModifiersKindTests: XCTestCase {
    func testActionKindMapsPreventDefaultToNoAction() {
        XCTAssertEqual(Scheme.Scrolling.Modifiers.Action.preventDefault.kind, .noAction)
    }

    func testInitFromDefaultActionKindCreatesAutoAction() {
        XCTAssertEqual(Scheme.Scrolling.Modifiers.Action(kind: .defaultAction), .auto)
    }
}
