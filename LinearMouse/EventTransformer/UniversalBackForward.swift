// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import GestureKit
import os.log

extension CGMouseButton {
    static let back = CGMouseButton(rawValue: 3)!
    static let forward = CGMouseButton(rawValue: 4)!
}

class UniversalBackForward: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "UniversalBackForward")

    private static let includeSet: Set<String> = [
        "org.mozilla.firefox"
    ]

    private func shouldHandleEvent(_ view: MouseEventView) -> Bool {
        guard let bundleIdentifier = view.targetBundleIdentifier else {
            return false
        }

        return Self.includeSet.contains(bundleIdentifier) || bundleIdentifier.hasPrefix("com.apple.")
    }

    // swiftlint:disable cyclomatic_complexity
    func transform(_ event: CGEvent) -> CGEvent? {
        let view = MouseEventView(event)
        guard let mouseButton = view.mouseButton else {
            return event
        }
        guard [.back, .forward].contains(mouseButton) else {
            return event
        }

        let targetBundleIdentifierString = view.targetBundleIdentifier ?? "(nil)"
        guard shouldHandleEvent(view) else {
            if event.type == .otherMouseDown {
                os_log("Ignore: %{public}@", log: Self.log, type: .debug, targetBundleIdentifierString)
            }
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

        os_log("Convert to swipe: %{public}@", log: Self.log, type: .debug, targetBundleIdentifierString)
        switch mouseButton {
        case .back:
            if let event = GestureEvent(navigationSwipeSource: nil, direction: .swipeLeft) {
                event.post(tap: .cghidEventTap)
            }
        case .forward:
            if let event = GestureEvent(navigationSwipeSource: nil, direction: .swipeRight) {
                event.post(tap: .cghidEventTap)
            }
        default:
            break
        }
        return nil
    }
}
