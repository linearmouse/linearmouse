// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit

public enum KeySimulatorError: Error {
    case unsupportedKey
}

/// Simulate key presses.
public class KeySimulator {
    private let keyCodeResolver = KeyCodeResolver()

    private var flags = CGEventFlags()

    public init() {}

    private func postKey(_ key: Key, keyDown: Bool, tap: CGEventTapLocation? = nil) throws {
        var flagsToToggle = CGEventFlags()
        switch key {
        case .command, .commandRight:
            flagsToToggle.insert(.maskCommand)
            flagsToToggle.insert(.init(rawValue: UInt64(key == .command ? NX_DEVICELCMDKEYMASK : NX_DEVICERCMDKEYMASK)))
        case .shift, .shiftRight:
            flagsToToggle.insert(.maskShift)
            flagsToToggle
                .insert(.init(rawValue: UInt64(key == .shift ? NX_DEVICELSHIFTKEYMASK : NX_DEVICERSHIFTKEYMASK)))
        case .option, .optionRight:
            flagsToToggle.insert(.maskAlternate)
            flagsToToggle.insert(.init(rawValue: UInt64(key == .option ? NX_DEVICELALTKEYMASK : NX_DEVICERALTKEYMASK)))
        case .control, .controlRight:
            flagsToToggle.insert(.maskControl)
            flagsToToggle.insert(.init(rawValue: UInt64(key == .control ? NX_DEVICELCTLKEYMASK : NX_DEVICERCTLKEYMASK)))
        default:
            break
        }

        if !flagsToToggle.isEmpty {
            if keyDown {
                flags.insert(flagsToToggle)
            } else {
                flags.remove(flagsToToggle)
            }
        }

        switch key {
        case .capsLock:
            postSystemDefinedKey(.capsLock, keyDown: keyDown)
            return
        default:
            break
        }

        guard let keyCode = keyCodeResolver.keyCode(for: key) else {
            throw KeySimulatorError.unsupportedKey
        }

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }

        event.flags = event.flags
            .subtracting([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            .union(flags)

        if !flagsToToggle.isEmpty {
            event.type = .flagsChanged
        }

        event.post(tap: tap ?? .cghidEventTap)
    }
}

public extension KeySimulator {
    func reset() {
        flags = []
    }

    func down(keys: [Key], tap: CGEventTapLocation? = nil) throws {
        for key in keys {
            try postKey(key, keyDown: true, tap: tap)
        }
    }

    func down(_ keys: Key..., tap: CGEventTapLocation? = nil) throws {
        try down(keys: keys, tap: tap)
    }

    func up(keys: [Key], tap: CGEventTapLocation? = nil) throws {
        for key in keys {
            try postKey(key, keyDown: false, tap: tap)
        }
    }

    func up(_ keys: Key..., tap: CGEventTapLocation? = nil) throws {
        try up(keys: keys, tap: tap)
    }

    func press(keys: [Key], tap: CGEventTapLocation? = nil) throws {
        try down(keys: keys, tap: tap)
        try up(keys: keys.reversed(), tap: tap)
    }

    func press(_ keys: Key..., tap: CGEventTapLocation? = nil) throws {
        try press(keys: keys, tap: tap)
    }

    func modifiedCGEventFlags(of event: CGEvent) -> CGEventFlags? {
        guard !flags.isEmpty else {
            return nil
        }

        guard event.type == .keyDown || event.type == .keyUp else {
            return nil
        }

        return event.flags.union(flags)
    }
}
