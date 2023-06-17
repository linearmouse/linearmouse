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

    private func postKey(_ key: Key, keyDown: Bool) throws {
        guard let keyCode = keyCodeResolver.keyCode(for: key) else {
            throw KeySimulatorError.unsupportedKey
        }

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }

        event.post(tap: .cghidEventTap)
    }

    func down(keys: [Key]) throws {
        for key in keys {
            try postKey(key, keyDown: true)
        }
    }

    func down(_ keys: Key...) throws {
        try down(keys: keys)
    }

    func up(keys: [Key]) throws {
        for key in keys {
            try postKey(key, keyDown: false)
        }
    }

    func up(_ keys: Key...) throws {
        try up(keys: keys)
    }

    func press(keys: [Key]) throws {
        try down(keys: keys)
        try up(keys: keys)
    }

    func press(_ keys: Key...) throws {
        try press(keys: keys)
    }
}
