// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Foundation
import LRUCache

class MouseEventView: EventView {
    var mouseButton: CGMouseButton? {
        get {
            guard let mouseButtonNumber = UInt32(exactly: event.getIntegerValueField(.mouseEventButtonNumber)) else {
                return nil
            }
            return CGMouseButton(rawValue: mouseButtonNumber)!
        }

        set {
            guard let newValue = newValue else {
                return
            }

            event.type = newValue.fixedCGEventType(of: event.type)
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(newValue.rawValue))
        }
    }

    var mouseButtonDescription: String {
        guard let mouseButton = mouseButton else {
            return "(nil)"
        }

        return (modifiers + ["<button \(mouseButton.rawValue)>"]).joined(separator: "+")
    }

    var sourcePid: pid_t? {
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid > 0 else {
            return nil
        }
        return pid
    }

    var targetPid: pid_t? {
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard pid > 0 else {
            return nil
        }
        return pid
    }

    var mouseLocationWindowID: CGWindowID {
        CGWindowID(NSWindow.windowNumber(
            at: NSPointFromCGPoint(event.unflippedLocation),
            belowWindowWithWindowNumber: 0
        ))
    }
}
