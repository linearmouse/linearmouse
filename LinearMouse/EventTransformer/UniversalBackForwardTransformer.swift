// MIT License
// Copyright (c) 2021-2023 LinearMouse

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

    private let interestedButtons: Set<CGMouseButton>

    init(universalBackForward: Scheme.Buttons.UniversalBackForward) {
        switch universalBackForward {
        case .none:
            interestedButtons = []
        case .both:
            interestedButtons = [.back, .forward]
        case .backOnly:
            interestedButtons = [.back]
        case .forwardOnly:
            interestedButtons = [.forward]
        }
    }

    private func shouldHandleEvent(_ view: MouseEventView) -> Bool {
        guard let mouseButton = view.mouseButton else {
            return false
        }

        guard interestedButtons.contains(mouseButton) else {
            return false
        }

        guard let bundleIdentifier = view.targetPid?.bundleIdentifier else {
            return false
        }

        return Self.includes.contains {
            if $0.hasSuffix("*") {
                return bundleIdentifier.hasPrefix($0.dropLast())
            } else {
                return bundleIdentifier == $0
            }
        }
    }

    // swiftlint:disable cyclomatic_complexity
    func transform(_ event: CGEvent) -> CGEvent? {
        let view = MouseEventView(event)

        let targetBundleIdentifierString = view.targetPid?.bundleIdentifier ?? "(nil)"
        guard shouldHandleEvent(view) else {
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
        switch view.mouseButton {
        case CGMouseButton.back:
            if let event = GestureEvent(navigationSwipeSource: nil, direction: .swipeLeft) {
                event.post(tap: .cgSessionEventTap)
            }
        case CGMouseButton.forward:
            if let event = GestureEvent(navigationSwipeSource: nil, direction: .swipeRight) {
                event.post(tap: .cgSessionEventTap)
            }
        default:
            break
        }
        return nil
    }
}
