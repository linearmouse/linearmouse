// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

final class AccessibilityBypassRuleTests: XCTestCase {
    private let matcher = AccessibilityBypassRuleMatcher(
        rules: AccessibilityBypassRule.autoScrollRules,
        scrollableRoles: ["AXWebArea", "AXScrollArea"]
    )

    func testChromeFullWindowGroupRuleMatchesHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: chromeFullWindowGroupSnapshot(),
            in: chromeContext()
        )

        XCTAssertEqual(rule?.name, "chromeFullWindowGroupHitTestHole")
    }

    func testChromeFullWindowGroupRuleRequiresChromeBundle() {
        let rule = matcher.firstMatchingRule(
            for: chromeFullWindowGroupSnapshot(),
            in: AccessibilityBypassRuleContext(
                bundleIdentifier: "com.apple.Safari",
                point: testPoint
            )
        )

        XCTAssertNil(rule)
    }

    func testChromeFullWindowGroupRuleDoesNotMatchWhenChildContainsPoint() {
        let rule = matcher.firstMatchingRule(
            for: chromeFullWindowGroupSnapshot(children: [
                AccessibilityBypassChildSnapshot(
                    role: "AXGroup",
                    frame: CGRect(x: 1000, y: 40, width: 120, height: 40)
                )
            ]),
            in: chromeContext()
        )

        XCTAssertNil(rule)
    }

    func testChromeFullWindowGroupRuleDoesNotMatchScrollableElement() {
        let rule = matcher.firstMatchingRule(
            for: chromeFullWindowGroupSnapshot(hasVerticalScrollBar: true),
            in: chromeContext()
        )

        XCTAssertNil(rule)
    }

    func testChromeFullWindowGroupRuleRequiresMatchingParentFrame() {
        let rule = matcher.firstMatchingRule(
            for: chromeFullWindowGroupSnapshot(
                parentFrame: CGRect(x: 63, y: 30, width: 1600, height: 900)
            ),
            in: chromeContext()
        )

        XCTAssertNil(rule)
    }

    func testBraveTabStripRuleMatchesDomClassListHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: braveTabStripGroupSnapshot(),
            in: braveContext()
        )

        XCTAssertEqual(rule?.name, "braveTabStripGroupHitTestHole")
    }

    func testBraveTabStripRuleRequiresBraveBundle() {
        let rule = matcher.firstMatchingRule(
            for: braveTabStripGroupSnapshot(),
            in: chromeContext()
        )

        XCTAssertNil(rule)
    }

    func testBraveTabStripRuleRequiresTabStripDomClass() {
        let rule = matcher.firstMatchingRule(
            for: braveTabStripGroupSnapshot(domClassList: []),
            in: braveContext()
        )

        XCTAssertNil(rule)
    }

    private var testPoint: CGPoint {
        CGPoint(x: 1067, y: 59)
    }

    private var fullWindowFrame: CGRect {
        CGRect(x: 63, y: 30, width: 1857, height: 1050)
    }

    private func chromeContext() -> AccessibilityBypassRuleContext {
        AccessibilityBypassRuleContext(
            bundleIdentifier: "com.google.Chrome",
            point: testPoint
        )
    }

    private func braveContext() -> AccessibilityBypassRuleContext {
        AccessibilityBypassRuleContext(
            bundleIdentifier: "com.brave.Browser",
            point: testPoint
        )
    }

    private func chromeFullWindowGroupSnapshot(
        parentFrame: CGRect? = nil,
        children: [AccessibilityBypassChildSnapshot] = [
            AccessibilityBypassChildSnapshot(
                role: "AXGroup",
                frame: CGRect(x: 1322, y: 102, width: 403, height: 84)
            )
        ],
        hasVerticalScrollBar: Bool = false
    ) -> AccessibilityBypassElementSnapshot {
        AccessibilityBypassElementSnapshot(
            depth: 0,
            role: "AXGroup",
            subrole: nil,
            actions: [],
            frame: fullWindowFrame,
            parentRole: "AXWindow",
            parentFrame: parentFrame ?? fullWindowFrame,
            children: children,
            hasVerticalScrollBar: hasVerticalScrollBar
        )
    }

    private func braveTabStripGroupSnapshot(
        domClassList: [String] = ["TabStrip::TabDragContextImpl"]
    ) -> AccessibilityBypassElementSnapshot {
        AccessibilityBypassElementSnapshot(
            depth: 0,
            role: "AXGroup",
            subrole: nil,
            actions: [],
            frame: CGRect(x: 166, y: 52, width: 494, height: 41),
            parentRole: "AXGroup",
            parentFrame: CGRect(x: 166, y: 52, width: 494, height: 41),
            children: [],
            domClassList: domClassList
        )
    }
}
