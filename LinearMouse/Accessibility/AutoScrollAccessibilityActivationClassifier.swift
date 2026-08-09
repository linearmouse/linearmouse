// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
import CoreGraphics
import Foundation

struct AutoScrollAccessibilityActivationClassifier {
    private static let domClassListAttribute = "AXDOMClassList" as CFString
    private static let maxParentDepth = 20
    private static let standardWindowButtonAttributes = [
        kAXCloseButtonAttribute as CFString,
        kAXMinimizeButtonAttribute as CFString,
        kAXZoomButtonAttribute as CFString,
        kAXFullScreenButtonAttribute as CFString
    ]
    private static let excludedRoles: Set<String> = [
        "AXMenuBar",
        "AXMenuBarItem",
        "AXMenu",
        "AXMenuItem",
        "AXMenuButton",
        "AXPopUpButton",
        "AXTabGroup",
        "AXToolbar"
    ]
    private static let excludedSubroles: Set<String> = [
        "AXTabButton",
        "AXMenuItem",
        "AXSortButton"
    ]
    private static let webContentRoles: Set<String> = [
        "AXWebArea",
        "AXScrollArea"
    ]
    private static let pressableRoles: Set<String> = [
        "AXLink",
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXComboBox",
        "AXDisclosureTriangle",
        "AXSwitch"
    ]

    private let elementQuery: AccessibilityElementQuerying
    private let bypassRuleMatcher: AccessibilityBypassRuleMatcher
    private let accessibilityHitTestRetryDelay: () -> Void

    init(
        elementQuery: AccessibilityElementQuerying = AccessibilityElementQuery(),
        bypassRuleMatcher: AccessibilityBypassRuleMatcher = AccessibilityBypassRuleMatcher(
            rules: AccessibilityBypassRule.autoScrollRules,
            scrollableRoles: Self.webContentRoles
        ),
        accessibilityHitTestRetryDelay: @escaping () -> Void = {
            Thread.sleep(forTimeInterval: 0.005)
        }
    ) {
        self.elementQuery = elementQuery
        self.bypassRuleMatcher = bypassRuleMatcher
        self.accessibilityHitTestRetryDelay = accessibilityHitTestRetryDelay
    }

    func classify(at point: CGPoint) -> AutoScrollActivationClassification {
        let initialResult = hitAccessibilityElement(at: point)
        let initialProbe = AutoScrollActivationProbe(point: point, hit: initialResult.hit)
        let resolvedProbe = refineActivationProbe(
            from: initialProbe,
            shouldRetryAtSamePoint: initialResult.shouldRetryAtSamePoint
        )
        return AutoScrollActivationClassification(initial: initialProbe, resolved: resolvedProbe)
    }

    static func isPressableActivationElement(role: String?, actions: [String]) -> Bool {
        guard let role,
              pressableRoles.contains(role) else {
            return false
        }

        if role == "AXLink" {
            return true
        }

        return actions.contains(kAXPressAction as String)
    }

    private func refineActivationProbe(
        from initialProbe: AutoScrollActivationProbe,
        shouldRetryAtSamePoint: Bool
    ) -> AutoScrollActivationProbe {
        guard shouldRetryAtSamePoint,
              initialProbe.hit.requiresRetry else {
            return initialProbe
        }

        // Chromium documents that its first synchronous hit test can be approximate and
        // that a subsequent hit test can use the asynchronously resolved renderer result:
        // https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/browser/how_a11y_works_3.md#Hit-testing
        // Chromium's regression test expects the first cached hit test to miss and the
        // second hit test at the same point to return the correct element:
        // https://chromium.googlesource.com/chromium/src/+/HEAD/content/browser/accessibility/hit_testing_browsertest.cc#710
        // Safari also returned a transient kAXErrorNotImplemented during cold-start testing.
        // Give either result a small window, then retry the original point so an adjacent
        // control cannot change the activation decision.
        accessibilityHitTestRetryDelay()
        return AutoScrollActivationProbe(
            point: initialProbe.point,
            hit: hitAccessibilityElement(at: initialProbe.point).hit
        )
    }

    private func hitAccessibilityElement(at point: CGPoint) -> AccessibilityHitTestResult {
        let hitElement: AXUIElement?
        switch elementQuery.systemWideElement(at: point) {
        case let .success(value):
            hitElement = value
        case let .failure(error):
            return Self.failedQueryResult(stage: "hitTest", error: error, path: [])
        }

        guard let hitElement else {
            return .certain(.nonPressable(diagnostic: nil, path: []))
        }

        var currentElement: AXUIElement? = hitElement
        var path: [String] = []
        var isInsideWebContent = false
        var hasBrowserAccessibilitySignal = false
        for depth in 0 ..< Self.maxParentDepth {
            guard let element = currentElement else {
                return .init(
                    hit: .nonPressable(diagnostic: nil, path: path),
                    shouldRetryAtSamePoint: hasBrowserAccessibilitySignal
                )
            }

            let role: String?
            switch elementQuery.requiredStringValue(of: kAXRoleAttribute as CFString, on: element) {
            case let .success(value):
                role = value
            case let .failure(error):
                return Self.failedQueryResult(stage: "role", error: error, path: path)
            }

            let subrole: String?
            switch elementQuery.optionalStringValue(of: kAXSubroleAttribute as CFString, on: element) {
            case let .success(value):
                subrole = value
            case let .failure(error):
                return Self.failedQueryResult(stage: "subrole", error: error, path: path)
            }

            let actions: [String]
            if Self.requiresActionNames(role: role, depth: depth) {
                switch elementQuery.optionalActionNames(of: element) {
                case let .success(value):
                    actions = value
                case let .failure(error):
                    return Self.failedQueryResult(stage: "actions", error: error, path: path)
                }
            } else {
                actions = []
            }

            path.append(Self.pathEntry(role: role, subrole: subrole, actions: actions))

            if let role, Self.webContentRoles.contains(role) {
                isInsideWebContent = true
                if role == "AXWebArea" {
                    hasBrowserAccessibilitySignal = true
                }
            }

            // Native controls can return before querying browser-only AX attributes.
            if !isInsideWebContent,
               Self.isExcludedActivationElement(role: role, subrole: subrole) {
                return .certain(.pressable(path: path))
            }

            if Self.isPressableActivationElement(role: role, actions: actions) {
                return .certain(.pressable(path: path))
            }

            let domClassList = domClassList(of: element)
            hasBrowserAccessibilitySignal = hasBrowserAccessibilitySignal || !domClassList.isEmpty
            if matchingBypassRule(
                element,
                depth: depth,
                role: role,
                subrole: subrole,
                actions: actions,
                domClassList: domClassList,
                at: point
            ) != nil {
                return .certain(.pressable(path: path))
            }

            switch elementQuery.optionalElementValue(of: kAXParentAttribute as CFString, on: element) {
            case let .success(value):
                currentElement = value
            case let .failure(error):
                return Self.failedQueryResult(stage: "parent", error: error, path: path)
            }
        }

        return .uncertain(.nonPressable(diagnostic: "depthLimit", path: path))
    }

    private static func failedQueryResult(
        stage: String,
        error: AXError,
        path: [String]
    ) -> AccessibilityHitTestResult {
        let hit = AutoScrollActivationHit.nonPressable(
            diagnostic: "\(stage).\(error.linearMouseDescription)",
            path: path
        )

        switch error {
        case .cannotComplete, .notImplemented:
            return .uncertain(hit)
        default:
            return .certain(hit)
        }
    }

    private static func requiresActionNames(role: String?, depth: Int) -> Bool {
        guard let role else {
            return false
        }

        return pressableRoles.contains(role) || (depth == 0 && role == "AXGroup")
    }

    private static func isExcludedActivationElement(role: String?, subrole: String?) -> Bool {
        if let role, excludedRoles.contains(role) {
            return true
        }

        if let subrole, excludedSubroles.contains(subrole) {
            return true
        }

        return false
    }

    private func matchingBypassRule(
        _ element: AXUIElement,
        depth: Int,
        role: String?,
        subrole: String?,
        actions: [String],
        domClassList: [String],
        at point: CGPoint
    ) -> AccessibilityBypassRule? {
        bypassRuleMatcher.firstMatchingRule(
            for: bypassElementSnapshot(
                element,
                depth: depth,
                role: role,
                subrole: subrole,
                actions: actions,
                domClassList: domClassList
            ),
            in: AccessibilityBypassRuleContext(
                point: point
            )
        )
    }

    private func bypassElementSnapshot(
        _ element: AXUIElement,
        depth: Int,
        role: String?,
        subrole: String?,
        actions: [String],
        domClassList: [String]
    ) -> AccessibilityBypassElementSnapshot {
        let needsFullWindowGroupSnapshot = depth == 0
            && role == "AXGroup"
            && subrole == nil
            && actions.isEmpty
        let needsWindowSnapshot = role == "AXWindow"
        // Geometry, child enumeration, and scrollbar queries cross the process boundary.
        // Fetch them only when the cheap rule conditions leave a possible match.
        let parent = needsFullWindowGroupSnapshot ? optionalParent(of: element) : nil

        return AccessibilityBypassElementSnapshot(
            depth: depth,
            role: role,
            subrole: subrole,
            actions: actions,
            frame: needsFullWindowGroupSnapshot || needsWindowSnapshot ? frame(of: element) : nil,
            parentRole: parent.flatMap { self.role(of: $0) },
            parentFrame: parent.flatMap { frame(of: $0) },
            children: needsFullWindowGroupSnapshot ? immediateChildren(of: element).map(childSnapshot) : [],
            hasVerticalScrollBar: needsFullWindowGroupSnapshot
                && hasAttributeValue(kAXVerticalScrollBarAttribute as CFString, on: element),
            hasHorizontalScrollBar: needsFullWindowGroupSnapshot
                && hasAttributeValue(kAXHorizontalScrollBarAttribute as CFString, on: element),
            domClassList: domClassList,
            standardWindowButtonFrames: needsWindowSnapshot ? standardWindowButtonFrames(of: element) : []
        )
    }

    private func standardWindowButtonFrames(of window: AXUIElement) -> [CGRect] {
        for attribute in Self.standardWindowButtonAttributes {
            guard case let .success(button?) = elementQuery.optionalElementValue(
                of: attribute,
                on: window
            ) else {
                continue
            }

            if let frame = frame(of: button) {
                return [frame]
            }
        }

        return []
    }

    private func domClassList(of element: AXUIElement) -> [String] {
        guard case let .success(value) = elementQuery.optionalAttributeValue(
            of: Self.domClassListAttribute,
            on: element
        ) else {
            return []
        }

        return value as? [String] ?? []
    }

    private func hasAttributeValue(_ attribute: CFString, on element: AXUIElement) -> Bool {
        guard case let .success(value) = elementQuery.optionalAttributeValue(of: attribute, on: element) else {
            return false
        }

        return value != nil
    }

    private func immediateChildren(of element: AXUIElement) -> [AXUIElement] {
        if case let .success(children?) = elementQuery.optionalElementArrayValue(
            of: kAXVisibleChildrenAttribute as CFString,
            on: element
        ) {
            return children
        }

        if case let .success(children?) = elementQuery.optionalElementArrayValue(
            of: kAXChildrenAttribute as CFString,
            on: element
        ) {
            return children
        }

        return []
    }

    private func childSnapshot(_ element: AXUIElement) -> AccessibilityBypassChildSnapshot {
        AccessibilityBypassChildSnapshot(
            role: role(of: element),
            frame: frame(of: element)
        )
    }

    private func optionalParent(of element: AXUIElement) -> AXUIElement? {
        guard case let .success(parent) = elementQuery.optionalElementValue(
            of: kAXParentAttribute as CFString,
            on: element
        ) else {
            return nil
        }

        return parent
    }

    private func role(of element: AXUIElement) -> String? {
        guard case let .success(role) = elementQuery.requiredStringValue(
            of: kAXRoleAttribute as CFString,
            on: element
        ) else {
            return nil
        }

        return role
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard case let .success(frame) = elementQuery.optionalFrameValue(of: element) else {
            return nil
        }

        return frame
    }

    private static func pathEntry(role: String?, subrole: String?, actions: [String]) -> String {
        let roleDescription = role ?? "?"
        let subroleDescription = subrole.map { "/\($0)" } ?? ""
        let pressDescription = actions.contains(kAXPressAction as String) ? "[press]" : ""
        return "\(roleDescription)\(subroleDescription)\(pressDescription)"
    }
}

struct AutoScrollActivationClassification {
    let initial: AutoScrollActivationProbe
    let resolved: AutoScrollActivationProbe
}

struct AutoScrollActivationProbe {
    let point: CGPoint
    let hit: AutoScrollActivationHit
}

private struct AccessibilityHitTestResult {
    let hit: AutoScrollActivationHit
    let shouldRetryAtSamePoint: Bool

    static func certain(_ hit: AutoScrollActivationHit) -> Self {
        .init(hit: hit, shouldRetryAtSamePoint: false)
    }

    static func uncertain(_ hit: AutoScrollActivationHit) -> Self {
        .init(hit: hit, shouldRetryAtSamePoint: true)
    }
}

enum AutoScrollActivationHit {
    case pressable(path: [String])
    case nonPressable(diagnostic: String?, path: [String])

    var path: [String] {
        switch self {
        case let .pressable(path):
            path
        case let .nonPressable(_, path):
            path
        }
    }

    var summary: String {
        switch self {
        case .pressable:
            "pressable"
        case let .nonPressable(diagnostic, _):
            diagnostic.map { "nonPressable.\($0)" } ?? "nonPressable"
        }
    }

    var isPressable: Bool {
        if case .pressable = self {
            return true
        }
        return false
    }

    var requiresRetry: Bool {
        !isPressable
    }
}
