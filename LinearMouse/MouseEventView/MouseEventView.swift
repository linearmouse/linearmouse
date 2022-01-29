//
//  EventView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

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
