// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
import CoreGraphics

struct AutoScrollAccessibilityActivationClassifier {
    private static let domClassListAttribute = "AXDOMClassList" as CFString
    private static let maxParentDepth = 20
    private static let probeRadius: CGFloat = 4
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

    init(
        elementQuery: AccessibilityElementQuerying = AccessibilityElementQuery(),
        bypassRuleMatcher: AccessibilityBypassRuleMatcher = AccessibilityBypassRuleMatcher(
            rules: AccessibilityBypassRule.autoScrollRules,
            scrollableRoles: Self.webContentRoles
        )
    ) {
        self.elementQuery = elementQuery
        self.bypassRuleMatcher = bypassRuleMatcher
    }

    func classify(at point: CGPoint) -> AutoScrollActivationClassification {
        let initialProbe = AutoScrollActivationProbe(point: point, hit: hitAccessibilityElement(at: point))
        let resolvedProbe = refineActivationProbe(from: initialProbe)
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

    private func refineActivationProbe(from initialProbe: AutoScrollActivationProbe) -> AutoScrollActivationProbe {
        guard initialProbe.hit.requiresAdditionalSampling else {
            return initialProbe
        }

        // Browser accessibility trees can return a generic container chain for a point that
        // is visually still inside a link. Probe a few nearby points and trust any result
        // that clearly says "do not start autoscroll".
        var bestProbe = initialProbe
        for point in accessibilityProbePoints(around: initialProbe.point) {
            let sampledProbe = AutoScrollActivationProbe(point: point, hit: hitAccessibilityElement(at: point))
            if sampledProbe.hit.suppressesAutoscroll {
                return sampledProbe
            }

            if sampledProbe.hit.priority > bestProbe.hit.priority {
                bestProbe = sampledProbe
            }
        }

        return bestProbe
    }

    private func accessibilityProbePoints(around point: CGPoint) -> [CGPoint] {
        let offsets = [
            CGPoint.zero,
            CGPoint(x: -Self.probeRadius, y: 0),
            CGPoint(x: Self.probeRadius, y: 0),
            CGPoint(x: 0, y: -Self.probeRadius),
            CGPoint(x: 0, y: Self.probeRadius),
            CGPoint(x: -Self.probeRadius, y: -Self.probeRadius),
            CGPoint(x: -Self.probeRadius, y: Self.probeRadius),
            CGPoint(x: Self.probeRadius, y: -Self.probeRadius),
            CGPoint(x: Self.probeRadius, y: Self.probeRadius)
        ]

        return offsets.map { offset in
            CGPoint(x: point.x + offset.x, y: point.y + offset.y)
        }
    }

    private func hitAccessibilityElement(at point: CGPoint) -> AutoScrollActivationHit {
        let hitElement: AXUIElement?
        switch elementQuery.systemWideElement(at: point) {
        case let .success(value):
            hitElement = value
        case let .failure(error):
            return .unknown(reason: "hitTest.\(error.linearMouseDescription)", path: [])
        }

        guard let hitElement else {
            return .nonPressable(path: [])
        }

        var currentElement: AXUIElement? = hitElement
        var path: [String] = []
        var isInsideWebContent = false
        for depth in 0 ..< Self.maxParentDepth {
            guard let element = currentElement else {
                return .nonPressable(path: path)
            }

            let role: String?
            switch elementQuery.requiredStringValue(of: kAXRoleAttribute as CFString, on: element) {
            case let .success(value):
                role = value
            case let .failure(error):
                return .unknown(reason: "role.\(error.linearMouseDescription)", path: path)
            }

            let subrole: String?
            switch elementQuery.optionalStringValue(of: kAXSubroleAttribute as CFString, on: element) {
            case let .success(value):
                subrole = value
            case let .failure(error):
                return .unknown(reason: "subrole.\(error.linearMouseDescription)", path: path)
            }

            let actions: [String]
            switch elementQuery.optionalActionNames(of: element) {
            case let .success(value):
                actions = value
            case let .failure(error):
                return .unknown(reason: "actions.\(error.linearMouseDescription)", path: path)
            }

            path.append(Self.pathEntry(role: role, subrole: subrole, actions: actions))

            if matchingBypassRule(
                element,
                depth: depth,
                role: role,
                subrole: subrole,
                actions: actions,
                at: point
            ) != nil {
                return .excludedChrome(path: path)
            }

            if let role, Self.webContentRoles.contains(role) {
                isInsideWebContent = true
            }

            // Once we have entered web content, ignore higher-level browser chrome ancestors
            // like tab groups or toolbars. Safari and Chromium often expose those above the
            // page content, and treating them as excluded chrome would block autoscroll on
            // normal page clicks.
            if !isInsideWebContent,
               Self.isExcludedActivationElement(role: role, subrole: subrole) {
                return .excludedChrome(path: path)
            }

            if Self.isPressableActivationElement(role: role, actions: actions) {
                return .pressable(path: path)
            }

            switch elementQuery.optionalElementValue(of: kAXParentAttribute as CFString, on: element) {
            case let .success(value):
                currentElement = value
            case let .failure(error):
                return .unknown(reason: "parent.\(error.linearMouseDescription)", path: path)
            }
        }

        return .unknown(reason: "depthLimit", path: path)
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
        at point: CGPoint
    ) -> AccessibilityBypassRule? {
        bypassRuleMatcher.firstMatchingRule(
            for: bypassElementSnapshot(
                element,
                depth: depth,
                role: role,
                subrole: subrole,
                actions: actions
            ),
            in: AccessibilityBypassRuleContext(
                bundleIdentifier: point.topmostWindowOwnerPid?.bundleIdentifier,
                point: point
            )
        )
    }

    private func bypassElementSnapshot(
        _ element: AXUIElement,
        depth: Int,
        role: String?,
        subrole: String?,
        actions: [String]
    ) -> AccessibilityBypassElementSnapshot {
        let parent = optionalParent(of: element)

        return AccessibilityBypassElementSnapshot(
            depth: depth,
            role: role,
            subrole: subrole,
            actions: actions,
            frame: frame(of: element),
            parentRole: parent.flatMap { self.role(of: $0) },
            parentFrame: parent.flatMap { frame(of: $0) },
            children: immediateChildren(of: element).map(childSnapshot),
            hasVerticalScrollBar: hasAttributeValue(kAXVerticalScrollBarAttribute as CFString, on: element),
            hasHorizontalScrollBar: hasAttributeValue(kAXHorizontalScrollBarAttribute as CFString, on: element),
            domClassList: domClassList(of: element)
        )
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

enum AutoScrollActivationHit {
    case pressable(path: [String])
    case excludedChrome(path: [String])
    case nonPressable(path: [String])
    case unknown(reason: String, path: [String])

    var path: [String] {
        switch self {
        case let .pressable(path):
            path
        case let .excludedChrome(path):
            path
        case let .nonPressable(path):
            path
        case let .unknown(_, path):
            path
        }
    }

    var summary: String {
        switch self {
        case .pressable:
            "pressable"
        case .excludedChrome:
            "excludedChrome"
        case .nonPressable:
            "nonPressable"
        case let .unknown(reason, _):
            "unknown.\(reason)"
        }
    }

    var suppressesAutoscroll: Bool {
        switch self {
        case .pressable, .excludedChrome:
            true
        case .nonPressable, .unknown:
            false
        }
    }

    var requiresAdditionalSampling: Bool {
        switch self {
        case .nonPressable, .unknown:
            true
        case .pressable, .excludedChrome:
            false
        }
    }

    var priority: Int {
        switch self {
        case .pressable, .excludedChrome:
            3
        case .nonPressable:
            2
        case .unknown:
            1
        }
    }
}
