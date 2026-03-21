// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
@testable import LinearMouse
import XCTest

final class AutoScrollTransformerTests: XCTestCase {
    func testPressableActivationElementAcceptsExplicitControls() {
        XCTAssertTrue(AutoScrollTransformer.isPressableActivationElement(role: "AXLink", actions: []))
        XCTAssertTrue(AutoScrollTransformer.isPressableActivationElement(
            role: "AXButton",
            actions: [kAXPressAction as String]
        ))
        XCTAssertTrue(AutoScrollTransformer.isPressableActivationElement(
            role: "AXCheckBox",
            actions: [kAXPressAction as String]
        ))
        XCTAssertTrue(AutoScrollTransformer.isPressableActivationElement(
            role: "AXComboBox",
            actions: [kAXPressAction as String]
        ))
    }

    func testPressableActivationElementRejectsGenericGroupEvenWithPressAction() {
        XCTAssertFalse(AutoScrollTransformer.isPressableActivationElement(
            role: "AXGroup",
            actions: [kAXPressAction as String]
        ))
    }

    func testPressableActivationElementRejectsControlWithoutPressActionWhenNeeded() {
        XCTAssertFalse(AutoScrollTransformer.isPressableActivationElement(role: "AXButton", actions: []))
        XCTAssertFalse(AutoScrollTransformer.isPressableActivationElement(
            role: nil,
            actions: [kAXPressAction as String]
        ))
    }
}
