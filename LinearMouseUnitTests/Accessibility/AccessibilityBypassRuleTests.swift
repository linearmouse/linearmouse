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

    func testStandardWindowTitleBarRuleMatchesZoteroTabStrip() {
        let rule = matcher.firstMatchingRule(
            for: zoteroWindowSnapshot(),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 150, y: 48))
        )

        XCTAssertEqual(rule?.name, "standardWindowTitleBar")
    }

    func testStandardWindowTitleBarRuleMatchesChromeTabStrip() {
        let rule = matcher.firstMatchingRule(
            for: standardWindowSnapshot(
                depth: 6,
                standardWindowButtonFrames: [
                    CGRect(x: 12, y: 42.5, width: 16, height: 16),
                    CGRect(x: 35, y: 42.5, width: 16, height: 16),
                    CGRect(x: 58, y: 42.5, width: 16, height: 16)
                ]
            ),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 200, y: 50))
        )

        XCTAssertEqual(rule?.name, "standardWindowTitleBar")
    }

    func testStandardWindowTitleBarRuleMatchesFirefoxTabStrip() {
        let rule = matcher.firstMatchingRule(
            for: standardWindowSnapshot(
                depth: 6,
                standardWindowButtonFrames: [
                    CGRect(x: 11, y: 44, width: 16, height: 16),
                    CGRect(x: 34, y: 44, width: 16, height: 16),
                    CGRect(x: 57, y: 44, width: 16, height: 16)
                ]
            ),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 500, y: 52))
        )

        XCTAssertEqual(rule?.name, "standardWindowTitleBar")
    }

    func testStandardWindowTitleBarRuleDoesNotMatchToolbarBelowTitleBar() {
        let rule = matcher.firstMatchingRule(
            for: zoteroWindowSnapshot(),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 500, y: 80))
        )

        XCTAssertNil(rule)
    }

    func testStandardWindowTitleBarRuleRequiresStandardWindowButtonGeometry() {
        let rule = matcher.firstMatchingRule(
            for: zoteroWindowSnapshot(standardWindowButtonFrames: []),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 150, y: 48))
        )

        XCTAssertNil(rule)
    }

    func testStandardWindowTitleBarRuleNeedsOnlyOneWindowButton() {
        let rule = matcher.firstMatchingRule(
            for: zoteroWindowSnapshot(
                standardWindowButtonFrames: [
                    CGRect(x: 13, y: 41, width: 12, height: 14)
                ]
            ),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 150, y: 48))
        )

        XCTAssertEqual(rule?.name, "standardWindowTitleBar")
    }

    func testStandardWindowTitleBarRuleRejectsPointOutsideWindow() {
        let rule = matcher.firstMatchingRule(
            for: zoteroWindowSnapshot(),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 1920, y: 48))
        )

        XCTAssertNil(rule)
    }

    func testStandardWindowTitleBarRuleDoesNotExpandWhenHitTestReturnsWindow() {
        let rule = matcher.firstMatchingRule(
            for: standardWindowSnapshot(
                depth: 0,
                standardWindowButtonFrames: [
                    CGRect(x: 10, y: 40, width: 12, height: 14)
                ]
            ),
            in: AccessibilityBypassRuleContext(point: CGPoint(x: 500, y: 80))
        )

        XCTAssertNil(rule)
    }

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

    private func zoteroWindowSnapshot(
        standardWindowButtonFrames: [CGRect] = [
            CGRect(x: 13, y: 41, width: 12, height: 14),
            CGRect(x: 33, y: 41, width: 12, height: 14),
            CGRect(x: 53, y: 41, width: 12, height: 14)
        ]
    ) -> AccessibilityBypassElementSnapshot {
        standardWindowSnapshot(
            depth: 6,
            standardWindowButtonFrames: standardWindowButtonFrames
        )
    }

    private func standardWindowSnapshot(
        depth: Int,
        subrole: String = "AXStandardWindow",
        standardWindowButtonFrames: [CGRect]
    ) -> AccessibilityBypassElementSnapshot {
        AccessibilityBypassElementSnapshot(
            depth: depth,
            role: "AXWindow",
            subrole: subrole,
            actions: ["AXRaise"],
            frame: CGRect(x: 0, y: 30, width: 1920, height: 971),
            children: [],
            standardWindowButtonFrames: standardWindowButtonFrames
        )
    }
}
