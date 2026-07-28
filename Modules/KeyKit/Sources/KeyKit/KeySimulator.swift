// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import os

public enum KeySimulatorError: Error {
    case unsupportedKey
}

/// Abstracts `KeySimulator` so call sites can inject a recorder/mock and avoid posting real key
/// events from unit tests.
public protocol KeySimulating: AnyObject {
    func down(keys: [Key], tap: CGEventTapLocation?) throws
    func up(keys: [Key], tap: CGEventTapLocation?) throws
    func press(keys: [Key], tap: CGEventTapLocation?) throws
    func press(keys: [Key], modifierFlags: CGEventFlags, tap: CGEventTapLocation?) throws
    func reset()
    func modifiedCGEventFlags(of event: CGEvent) -> CGEventFlags?
}

/// Simulate key presses.
public class KeySimulator: KeySimulating {
    typealias EventPoster = (_ event: CGEvent, _ tap: CGEventTapLocation?) -> Void

    private let keyCodeResolver = KeyCodeResolver()
    private let eventSourceUserData: Int64?
    private let eventPoster: EventPoster
    private let lock = NSLock()

    private var flags = CGEventFlags()

    public convenience init(eventSourceUserData: Int64? = nil) {
        self.init(eventSourceUserData: eventSourceUserData) { event, tap in
            event.post(tap: tap ?? .cghidEventTap)
        }
    }

    init(
        eventSourceUserData: Int64? = nil,
        eventPoster: @escaping EventPoster
    ) {
        self.eventSourceUserData = eventSourceUserData
        self.eventPoster = eventPoster
    }

    private func postKeyLocked(
        _ key: Key,
        keyDown: Bool,
        modifierFlags: CGEventFlags = [],
        tap: CGEventTapLocation? = nil
    ) throws {
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

        let eventFlags = flags.union(modifierFlags)
        guard let keyCode = keyCodeResolver.keyCode(for: key, modifiers: eventFlags) else {
            throw KeySimulatorError.unsupportedKey
        }

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }

        event.flags = event.flags
            .subtracting([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            .union(eventFlags)

        if !flagsToToggle.isEmpty {
            event.type = .flagsChanged
        }

        if let eventSourceUserData {
            event.setIntegerValueField(.eventSourceUserData, value: eventSourceUserData)
        }

        eventPoster(event, tap)
    }

    private func pressLocked(
        keys: [Key],
        modifierFlags: CGEventFlags = [],
        tap: CGEventTapLocation?
    ) {
        for key in keys {
            do {
                try postKeyLocked(
                    key,
                    keyDown: true,
                    modifierFlags: modifierFlags,
                    tap: tap
                )
            } catch {
                os_log(.error, "KeySimulator: keyDown failed for %{public}@: %{public}@", "\(key)", "\(error)")
            }
        }
        for key in keys.reversed() {
            do {
                try postKeyLocked(
                    key,
                    keyDown: false,
                    modifierFlags: modifierFlags,
                    tap: tap
                )
            } catch {
                os_log(.error, "KeySimulator: keyUp failed for %{public}@: %{public}@", "\(key)", "\(error)")
            }
        }
    }
}

public extension KeySimulator {
    func reset() {
        lock.withLock {
            flags = []
        }
    }

    func down(keys: [Key], tap: CGEventTapLocation? = nil) throws {
        try lock.withLock {
            for key in keys {
                try postKeyLocked(key, keyDown: true, tap: tap)
            }
        }
    }

    func down(_ keys: Key..., tap: CGEventTapLocation? = nil) throws {
        try down(keys: keys, tap: tap)
    }

    func up(keys: [Key], tap: CGEventTapLocation? = nil) throws {
        try lock.withLock {
            for key in keys {
                try postKeyLocked(key, keyDown: false, tap: tap)
            }
        }
    }

    func up(_ keys: Key..., tap: CGEventTapLocation? = nil) throws {
        try up(keys: keys, tap: tap)
    }

    func press(keys: [Key], tap: CGEventTapLocation? = nil) throws {
        lock.withLock {
            pressLocked(keys: keys, tap: tap)
        }
    }

    func press(_ keys: Key..., tap: CGEventTapLocation? = nil) throws {
        try press(keys: keys, tap: tap)
    }

    /// Presses keys with modifier flags attached to each generated event without synthesizing
    /// modifier key transitions.
    func press(
        keys: [Key],
        modifierFlags: CGEventFlags,
        tap: CGEventTapLocation? = nil
    ) throws {
        lock.withLock {
            pressLocked(keys: keys, modifierFlags: modifierFlags, tap: tap)
        }
    }

    func press(
        _ keys: Key...,
        modifierFlags: CGEventFlags,
        tap: CGEventTapLocation? = nil
    ) throws {
        try press(keys: keys, modifierFlags: modifierFlags, tap: tap)
    }

    func modifiedCGEventFlags(of event: CGEvent) -> CGEventFlags? {
        lock.withLock {
            guard !flags.isEmpty else {
                return nil
            }

            guard event.type == .keyDown || event.type == .keyUp else {
                return nil
            }

            return event.flags.union(flags)
        }
    }
}
