// MIT License
// Copyright (c) 2021-2023 LinearMouse

//
//  File.swift
//
//
//  Created by Jiahao Lu on 2023/6/17.
//
import AppKit

public enum KeySimulatorError: Error {
    case unsupportedKey
}

/// Simulate key presses.
public class KeySimulator {
    private let keyCodeResolver = KeyCodeResolver()

    public init() {}

    private func postKey(_ key: Key, keyDown: Bool, tap: CGEventTapLocation? = nil) throws {
        guard let keyCode = keyCodeResolver.keyCode(for: key) else {
            throw KeySimulatorError.unsupportedKey
        }

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }

        event.flags = .init(rawValue: 0)

        event.post(tap: tap ?? .cghidEventTap)
    }
}

public extension KeySimulator {
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
        try up(keys: keys, tap: tap)
    }

    func press(_ keys: Key..., tap: CGEventTapLocation? = nil) throws {
        try press(keys: keys, tap: tap)
    }
}
