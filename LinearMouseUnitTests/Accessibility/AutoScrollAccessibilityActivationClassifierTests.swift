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

    func testAccessibilityFailureInsideWebContentRequiresAdditionalSampling() {
        let hit = AutoScrollActivationHit.nonPressable(
            diagnostic: "role.cannotComplete",
            path: ["AXGroup"],
            isInsideWebContent: true
        )

        XCTAssertFalse(hit.isPressable)
        XCTAssertTrue(hit.requiresAdditionalSampling)
        XCTAssertEqual(hit.summary, "nonPressable.role.cannotComplete")
    }

    func testNonPressableHitOutsideWebContentSkipsAdditionalSampling() {
        let hit = AutoScrollActivationHit.nonPressable(
            diagnostic: "listContainer",
            path: ["AXOutline"],
            isInsideWebContent: false
        )

        XCTAssertFalse(hit.isPressable)
        XCTAssertFalse(hit.requiresAdditionalSampling)
        XCTAssertEqual(hit.summary, "nonPressable.listContainer")
    }

    func testAutoScrollStartsOnlyForNonPressableOrUnavailableHit() {
        XCTAssertFalse(AutoScrollTransformer.shouldStartAutoScroll(for: .pressable(path: [])))
        XCTAssertTrue(AutoScrollTransformer.shouldStartAutoScroll(for: .nonPressable(
            diagnostic: nil,
            path: [],
            isInsideWebContent: false
        )))
        XCTAssertTrue(AutoScrollTransformer.shouldStartAutoScroll(for: nil))
    }

    func testListContainerRoleStopsClimbingTablesOutlinesAndLists() {
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isListContainerRole("AXTable"))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isListContainerRole("AXOutline"))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isListContainerRole("AXList"))
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isListContainerRole("AXCell"))
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isListContainerRole("AXGroup"))
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isListContainerRole(nil))
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
