// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
@testable import LinearMouse
import XCTest

final class AutoScrollAccessibilityActivationClassifierTests: XCTestCase {
    func testPressableHitPreservesNativeEventWithoutAdditionalSampling() {
        let hit = AutoScrollActivationHit.pressable(path: ["AXButton[press]"])

        XCTAssertTrue(hit.isPressable)
        XCTAssertFalse(hit.requiresAdditionalSampling)
        XCTAssertEqual(hit.summary, "pressable")
    }

    func testAccessibilityFailureIsNonPressableWithDiagnostic() {
        let hit = AutoScrollActivationHit.nonPressable(
            diagnostic: "role.cannotComplete",
            path: ["AXGroup"]
        )

        XCTAssertFalse(hit.isPressable)
        XCTAssertTrue(hit.requiresAdditionalSampling)
        XCTAssertEqual(hit.summary, "nonPressable.role.cannotComplete")
    }

    func testAutoScrollStartsOnlyForNonPressableOrUnavailableHit() {
        XCTAssertFalse(AutoScrollTransformer.shouldStartAutoScroll(for: .pressable(path: [])))
        XCTAssertTrue(AutoScrollTransformer.shouldStartAutoScroll(for: .nonPressable(
            diagnostic: nil,
            path: []
        )))
        XCTAssertTrue(AutoScrollTransformer.shouldStartAutoScroll(for: nil))
    }

    func testPressableActivationElementAcceptsExplicitControls() {
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXLink",
            actions: []
        ))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXButton",
            actions: [kAXPressAction as String]
        ))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXCheckBox",
            actions: [kAXPressAction as String]
        ))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXComboBox",
            actions: [kAXPressAction as String]
        ))
    }

    func testPressableActivationElementRejectsGenericGroupEvenWithPressAction() {
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXGroup",
            actions: [kAXPressAction as String]
        ))
    }

    func testPressableActivationElementRejectsControlWithoutPressActionWhenNeeded() {
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXButton",
            actions: []
        ))
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: nil,
            actions: [kAXPressAction as String]
        ))
    }
}
