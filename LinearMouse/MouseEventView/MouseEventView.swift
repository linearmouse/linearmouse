// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import AppKit
import Foundation
import LRUCache

class MouseEventView {
    private static var bundleIdentifierCache = LRUCache<pid_t, String>(countLimit: 5)

    let event: CGEvent

    init(_ event: CGEvent) {
        self.event = event
    }

    var mouseButton: CGMouseButton? {
        guard let mouseButtonNumber = UInt32(exactly: event.getIntegerValueField(.mouseEventButtonNumber)) else {
            return nil
        }
        return CGMouseButton(rawValue: mouseButtonNumber)!
    }

    var modifierFlags: CGEventFlags {
        event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
    }

    var modifiers: [String] {
        [
            (CGEventFlags.maskCommand, "command"),
            (CGEventFlags.maskShift, "shift"),
            (CGEventFlags.maskAlternate, "option"),
            (CGEventFlags.maskControl, "control")
        ]
        .filter { modifierFlags.contains($0.0) }
        .map(\.1)
    }

    var mouseButtonDescription: String {
        guard let mouseButton = mouseButton else {
            return "(null)"
        }

        return (modifiers + ["<button \(mouseButton.rawValue)>"]).joined(separator: "+")
    }

    var targetBundleIdentifier: String? {
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard let bundleIdentifier = Self.bundleIdentifierCache.value(forKey: pid)
            ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        else {
            return nil
        }
        Self.bundleIdentifierCache.setValue(bundleIdentifier, forKey: pid)
        return bundleIdentifier
    }
}
