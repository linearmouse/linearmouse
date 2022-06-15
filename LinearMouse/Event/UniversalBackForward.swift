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
    /**
     Applications whose `CFBundleIdentifier` are contained in the set
     will be ignored by `UniversalBackForward` transformer.

     Keep it in alphabetical order if you want to change it.

     See: <https://github.com/linearmouse/linearmouse/issues/57>
     */
    private static let ignoreSet: Set = [
        "com.microsoft.VSCode",
        "com.microsoft.rdc.macos",
        "com.parallels.desktop.console",
        "com.valvesoftware.dota2",
        "com.vmware.fusion",
        "org.virtualbox.app.VirtualBox",
        "tv.parsec.www"
    ]

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "UniversalBackForward")

    private func targetInIgnoreSet(_ view: MouseEventView) -> Bool {
        guard let bundleIdentifier = view.targetBundleIdentifier else {
            return false
        }
        return Self.ignoreSet.contains(bundleIdentifier)
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

        // Skip applications in ignore set.
        let targetBundleIdentifierString = view.targetBundleIdentifier ?? "(nil)"
        guard !targetInIgnoreSet(view) else {
            if event.type == .otherMouseDown {
                os_log("Hit ignore set: %{public}@", log: Self.log, type: .debug, targetBundleIdentifierString)
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
