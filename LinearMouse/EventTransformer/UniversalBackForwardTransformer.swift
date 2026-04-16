// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import GestureKit
import os.log

class UniversalBackForwardTransformer: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "UniversalBackForward")

    private static let includes = [
        "com.apple.*",
        "com.binarynights.ForkLift*",
        "org.mozilla.firefox",
        "com.operasoftware.Opera"
    ]

    enum Replacement: Equatable {
        case mouseButton(CGMouseButton)
        case navigationSwipe(NavigationSwipeDirection)
    }

    enum NavigationSwipeDirection: Equatable {
        case left
        case right

        var hidDirection: IOHIDSwipeMask {
            switch self {
            case .left:
                return .swipeLeft
            case .right:
                return .swipeRight
            }
        }
    }

    private let universalBackForward: Scheme.Buttons.UniversalBackForward

    init(universalBackForward: Scheme.Buttons.UniversalBackForward) {
        self.universalBackForward = universalBackForward
    }

    static func interestedButtons(for universalBackForward: Scheme.Buttons.UniversalBackForward) -> Set<CGMouseButton> {
        switch universalBackForward {
        case .none:
            return []
        case .both:
            return [.back, .forward]
        case .backOnly:
            return [.back]
        case .forwardOnly:
            return [.forward]
        }
    }

    static func supportsTargetBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        return Self.includes.contains {
            if $0.hasSuffix("*") {
                return bundleIdentifier.hasPrefix($0.dropLast())
            }
            return bundleIdentifier == $0
        }
    }

    static func replacement(
        for mouseButton: CGMouseButton,
        universalBackForward: Scheme.Buttons.UniversalBackForward?,
        targetBundleIdentifier: String?
    ) -> Replacement {
        guard let universalBackForward,
              interestedButtons(for: universalBackForward).contains(mouseButton),
              supportsTargetBundleIdentifier(targetBundleIdentifier) else {
            return .mouseButton(mouseButton)
        }

        switch mouseButton {
        case .back:
            return .navigationSwipe(.left)
        case .forward:
            return .navigationSwipe(.right)
        default:
            return .mouseButton(mouseButton)
        }
    }

    @discardableResult
    static func postNavigationSwipeIfNeeded(
        for mouseButton: CGMouseButton,
        universalBackForward: Scheme.Buttons.UniversalBackForward?,
        targetBundleIdentifier: String?
    ) -> Bool {
        guard case let .navigationSwipe(direction) = replacement(
            for: mouseButton,
            universalBackForward: universalBackForward,
            targetBundleIdentifier: targetBundleIdentifier
        ) else {
            return false
        }

        guard let event = GestureEvent(
            navigationSwipeSource: nil,
            direction: direction.hidDirection
        ) else {
            return false
        }

        event.post(tap: .cgSessionEventTap)
        return true
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        if event.isGestureCleanupRelease {
            return event
        }

        let view = MouseEventView(event)
        guard let mouseButton = view.mouseButton else {
            return event
        }

        let targetBundleIdentifier = view.targetPid?.bundleIdentifier
        let targetBundleIdentifierString = targetBundleIdentifier ?? "(nil)"
        guard case let .navigationSwipe(direction) = Self.replacement(
            for: mouseButton,
            universalBackForward: universalBackForward,
            targetBundleIdentifier: targetBundleIdentifier
        ) else {
            return event
        }

        // We'll simulate swipes when back/forward button down
        // and eats corresponding mouse up events.
        switch event.type {
        case .otherMouseDown:
            break
        case .otherMouseUp:
            return nil
        default:
            return event
        }

        os_log("Convert to swipe: %{public}@", log: Self.log, type: .info, targetBundleIdentifierString)
        GestureEvent(navigationSwipeSource: nil, direction: direction.hidDirection)?
            .post(tap: .cgSessionEventTap)
        return nil
    }
}
