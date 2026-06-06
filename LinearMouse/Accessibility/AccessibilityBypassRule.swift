// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics

struct AccessibilityBypassRule {
    let name: String
    let bundleIdentifiers: Set<String>?
    let conditions: [AccessibilityBypassCondition]

    init(
        name: String,
        bundleIdentifiers: Set<String>? = nil,
        conditions: [AccessibilityBypassCondition]
    ) {
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.conditions = conditions
    }
}

extension AccessibilityBypassRule {
    static let autoScrollRules: [AccessibilityBypassRule] = [
        AccessibilityBypassRule(
            name: "chromeFullWindowGroupHitTestHole",
            bundleIdentifiers: ["com.google.Chrome"],
            conditions: [
                .depth(0),
                .role("AXGroup"),
                .subrole(nil),
                .actionsEmpty,
                .noScrollabilitySignal,
                .noChildContainingPoint,
                .parentRole("AXWindow"),
                .frameMatchesParent
            ]
        )
    ]
}

enum AccessibilityBypassCondition {
    case depth(Int)
    case role(String)
    case subrole(String?)
    case actionsEmpty
    case noScrollabilitySignal
    case noChildContainingPoint
    case parentRole(String)
    case frameMatchesParent
}

struct AccessibilityBypassRuleContext {
    let bundleIdentifier: String?
    let point: CGPoint
}

struct AccessibilityBypassElementSnapshot {
    let depth: Int
    let role: String?
    let subrole: String?
    let actions: [String]
    let frame: CGRect?
    let parentRole: String?
    let parentFrame: CGRect?
    let children: [AccessibilityBypassChildSnapshot]
    let hasVerticalScrollBar: Bool
    let hasHorizontalScrollBar: Bool

    init(
        depth: Int,
        role: String?,
        subrole: String? = nil,
        actions: [String] = [],
        frame: CGRect? = nil,
        parentRole: String? = nil,
        parentFrame: CGRect? = nil,
        children: [AccessibilityBypassChildSnapshot] = [],
        hasVerticalScrollBar: Bool = false,
        hasHorizontalScrollBar: Bool = false
    ) {
        self.depth = depth
        self.role = role
        self.subrole = subrole
        self.actions = actions
        self.frame = frame
        self.parentRole = parentRole
        self.parentFrame = parentFrame
        self.children = children
        self.hasVerticalScrollBar = hasVerticalScrollBar
        self.hasHorizontalScrollBar = hasHorizontalScrollBar
    }
}

struct AccessibilityBypassChildSnapshot {
    let role: String?
    let frame: CGRect?

    init(role: String?, frame: CGRect? = nil) {
        self.role = role
        self.frame = frame
    }
}

struct AccessibilityBypassRuleMatcher {
    let rules: [AccessibilityBypassRule]
    let scrollableRoles: Set<String>

    func firstMatchingRule(
        for element: AccessibilityBypassElementSnapshot,
        in context: AccessibilityBypassRuleContext
    ) -> AccessibilityBypassRule? {
        rules.first { rule in
            matches(rule, element: element, context: context)
        }
    }

    private func matches(
        _ rule: AccessibilityBypassRule,
        element: AccessibilityBypassElementSnapshot,
        context: AccessibilityBypassRuleContext
    ) -> Bool {
        if let bundleIdentifiers = rule.bundleIdentifiers {
            guard let bundleIdentifier = context.bundleIdentifier,
                  bundleIdentifiers.contains(bundleIdentifier) else {
                return false
            }
        }

        return rule.conditions.allSatisfy { condition in
            matches(condition, element: element, context: context)
        }
    }

    private func matches(
        _ condition: AccessibilityBypassCondition,
        element: AccessibilityBypassElementSnapshot,
        context: AccessibilityBypassRuleContext
    ) -> Bool {
        switch condition {
        case let .depth(expectedDepth):
            return element.depth == expectedDepth
        case let .role(expectedRole):
            return element.role == expectedRole
        case let .subrole(expectedSubrole):
            return element.subrole == expectedSubrole
        case .actionsEmpty:
            return element.actions.isEmpty
        case .noScrollabilitySignal:
            return !hasScrollabilitySignal(element)
        case .noChildContainingPoint:
            return !element.children.contains { child in
                child.frame?.contains(context.point) == true
            }
        case let .parentRole(expectedRole):
            return element.parentRole == expectedRole
        case .frameMatchesParent:
            guard let frame = element.frame,
                  let parentFrame = element.parentFrame else {
                return false
            }

            return framesApproximatelyMatch(frame, parentFrame)
        }
    }

    private func hasScrollabilitySignal(_ element: AccessibilityBypassElementSnapshot) -> Bool {
        if let role = element.role,
           scrollableRoles.contains(role) || role == "AXScrollBar" {
            return true
        }

        if element.hasVerticalScrollBar || element.hasHorizontalScrollBar {
            return true
        }

        return element.children.contains { child in
            child.role == "AXScrollBar"
        }
    }

    private func framesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 1
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
