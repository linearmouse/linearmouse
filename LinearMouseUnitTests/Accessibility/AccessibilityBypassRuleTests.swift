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

    func testChromiumTabStripRuleMatchesBraveHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: chromiumTabStripGroupSnapshot(),
            in: braveContext()
        )

        XCTAssertEqual(rule?.name, "chromiumTabStripDragContextHitTestHole")
    }

    func testChromiumTabStripRuleMatchesChromeHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: chromiumTabStripGroupSnapshot(),
            in: chromeContext()
        )

        XCTAssertEqual(rule?.name, "chromiumTabStripDragContextHitTestHole")
    }

    func testChromiumTabStripRuleDoesNotDependOnBrowserBundle() {
        let rule = matcher.firstMatchingRule(
            for: chromiumTabStripGroupSnapshot(),
            in: AccessibilityBypassRuleContext(
                bundleIdentifier: "com.example.ChromiumDerivative",
                point: testPoint
            )
        )

        XCTAssertEqual(rule?.name, "chromiumTabStripDragContextHitTestHole")
    }

    func testChromiumTabStripRuleDependsOnlyOnTabStripDomClass() {
        let snapshot = AccessibilityBypassElementSnapshot(
            depth: 8,
            role: "AXWebArea",
            subrole: "AXUnexpectedSubrole",
            actions: ["AXPress"],
            frame: nil,
            parentRole: nil,
            parentFrame: nil,
            children: [AccessibilityBypassChildSnapshot(role: "AXScrollBar")],
            hasVerticalScrollBar: true,
            hasHorizontalScrollBar: true,
            domClassList: ["unrelated", "TabStrip::TabDragContextImpl"]
        )

        let rule = matcher.firstMatchingRule(for: snapshot, in: braveContext())

        XCTAssertEqual(rule?.name, "chromiumTabStripDragContextHitTestHole")
    }

    func testChromiumTabStripRuleRequiresExactTabStripDomClass() {
        let rule = matcher.firstMatchingRule(
            for: chromiumTabStripGroupSnapshot(domClassList: ["TabStrip::TabDragContext"]),
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

    private func chromiumTabStripGroupSnapshot(
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
