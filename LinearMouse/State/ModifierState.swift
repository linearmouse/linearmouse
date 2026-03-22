// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation

final class ModifierState {
    static let shared = ModifierState()

    static let genericFlags: CGEventFlags = [
        .maskCommand,
        .maskShift,
        .maskAlternate,
        .maskControl
    ]

    static let sideSpecificFlags = CGEventFlags(rawValue: UInt64(
        NX_DEVICELCTLKEYMASK |
            NX_DEVICERCTLKEYMASK |
            NX_DEVICELSHIFTKEYMASK |
            NX_DEVICERSHIFTKEYMASK |
            NX_DEVICELALTKEYMASK |
            NX_DEVICERALTKEYMASK |
            NX_DEVICELCMDKEYMASK |
            NX_DEVICERCMDKEYMASK
    ))

    static let relevantFlags = genericFlags.union(sideSpecificFlags)

    private let lock = NSLock()
    private var currentFlagsStorage: CGEventFlags

    private init() {
        currentFlagsStorage = Self.normalize(CGEventSource.flagsState(.combinedSessionState))
    }

    var currentFlags: CGEventFlags {
        lock.lock()
        defer { lock.unlock() }
        return currentFlagsStorage
    }

    func update(with event: CGEvent) {
        guard [.flagsChanged, .keyDown, .keyUp].contains(event.type),
              !event.isLinearMouseSyntheticEvent else {
            return
        }

        lock.lock()
        currentFlagsStorage = Self.normalize(event.flags)
        lock.unlock()
    }

    static func normalize(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(relevantFlags)
    }

    static func generic(from flags: CGEventFlags) -> CGEventFlags {
        normalize(flags).intersection(genericFlags)
    }

    static func sideSpecific(from flags: CGEventFlags) -> CGEventFlags {
        normalize(flags).intersection(sideSpecificFlags)
    }
}
