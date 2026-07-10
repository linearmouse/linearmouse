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

    func testChromiumFullWindowGroupRuleMatchesChromeHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(),
            in: testContext()
        )

        XCTAssertEqual(rule?.name, "chromiumFullWindowGroupHitTestHole")
    }

    func testChromiumFullWindowGroupRuleMatchesBraveHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(domClassList: ["BraveBrowserRootView"]),
            in: testContext()
        )

        XCTAssertEqual(rule?.name, "chromiumFullWindowGroupHitTestHole")
    }

    func testChromiumFullWindowGroupRuleMatchesDerivedBrowserRootView() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(domClassList: ["ExampleBrowserRootView"]),
            in: testContext()
        )

        XCTAssertEqual(rule?.name, "chromiumFullWindowGroupHitTestHole")
    }

    func testChromiumFullWindowGroupRuleRequiresBrowserRootViewClass() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(domClassList: ["RootView"]),
            in: testContext()
        )

        XCTAssertNil(rule)
    }

    func testChromiumFullWindowGroupRuleDoesNotMatchWebContentContainer() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(parentRole: "AXWebArea"),
            in: testContext()
        )

        XCTAssertNil(rule)
    }

    func testChromiumFullWindowGroupRuleDoesNotMatchWhenChildContainsPoint() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(children: [
                AccessibilityBypassChildSnapshot(
                    role: "AXGroup",
                    frame: CGRect(x: 1000, y: 40, width: 120, height: 40)
                )
            ]),
            in: testContext()
        )

        XCTAssertNil(rule)
    }

    func testChromiumFullWindowGroupRuleDoesNotMatchScrollableElement() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(hasVerticalScrollBar: true),
            in: testContext()
        )

        XCTAssertNil(rule)
    }

    func testChromiumFullWindowGroupRuleRequiresMatchingParentFrame() {
        let rule = matcher.firstMatchingRule(
            for: chromiumFullWindowGroupSnapshot(
                parentFrame: CGRect(x: 63, y: 30, width: 1600, height: 900)
            ),
            in: testContext()
        )

        XCTAssertNil(rule)
    }

    func testChromiumTabStripRuleMatchesBraveHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: chromiumTabStripGroupSnapshot(),
            in: testContext()
        )

        XCTAssertEqual(rule?.name, "chromiumTabStripDragContextHitTestHole")
    }

    func testChromiumTabStripRuleMatchesChromeHitTestHole() {
        let rule = matcher.firstMatchingRule(
            for: chromiumTabStripGroupSnapshot(),
            in: testContext()
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

        let rule = matcher.firstMatchingRule(for: snapshot, in: testContext())

        XCTAssertEqual(rule?.name, "chromiumTabStripDragContextHitTestHole")
    }

    func testChromiumTabStripRuleRequiresExactTabStripDomClass() {
        let rule = matcher.firstMatchingRule(
            for: chromiumTabStripGroupSnapshot(domClassList: ["TabStrip::TabDragContext"]),
            in: testContext()
        )

        XCTAssertNil(rule)
    }

    private var testPoint: CGPoint {
        CGPoint(x: 1067, y: 59)
    }

    private var fullWindowFrame: CGRect {
        CGRect(x: 63, y: 30, width: 1857, height: 1050)
    }

    private func testContext() -> AccessibilityBypassRuleContext {
        AccessibilityBypassRuleContext(point: testPoint)
    }

    private func chromiumFullWindowGroupSnapshot(
        parentRole: String? = "AXWindow",
        parentFrame: CGRect? = nil,
        children: [AccessibilityBypassChildSnapshot] = [
            AccessibilityBypassChildSnapshot(
                role: "AXGroup",
                frame: CGRect(x: 1322, y: 102, width: 403, height: 84)
            )
        ],
        hasVerticalScrollBar: Bool = false,
        domClassList: [String] = ["BrowserRootView"]
    ) -> AccessibilityBypassElementSnapshot {
        AccessibilityBypassElementSnapshot(
            depth: 0,
            role: "AXGroup",
            subrole: nil,
            actions: [],
            frame: fullWindowFrame,
            parentRole: parentRole,
            parentFrame: parentFrame ?? fullWindowFrame,
            children: children,
            hasVerticalScrollBar: hasVerticalScrollBar,
            domClassList: domClassList
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
