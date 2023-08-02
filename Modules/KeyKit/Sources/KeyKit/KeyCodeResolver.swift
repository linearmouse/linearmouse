// MIT License
// Copyright (c) 2021-2023 LinearMouse

import AppKit
import Carbon
import Combine
import Foundation

/// Keyboard layout-independent key code resolver.
public class KeyCodeResolver {
    private var subscriptions = Set<AnyCancellable>()
    private var mapping: [String: CGKeyCode] = [:]
    private var reversedMapping: [CGKeyCode: Key] = [:]

    public init() {
        DistributedNotificationCenter.default
            .publisher(for: .init(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
            .sink { [weak self] _ in
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                    self?.updateMapping()
                }
            }
            .store(in: &subscriptions)

        DistributedNotificationCenter.default
            .publisher(for: .init(kTISNotifySelectedKeyboardInputSourceChanged as String))
            .sink { [weak self] _ in
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                    self?.updateMapping()
                }
            }
            .store(in: &subscriptions)

        updateMapping()
    }

    private func updateMapping() {
        var newMapping: [String: CGKeyCode] = [:]
        var newReversedMapping: [CGKeyCode: Key] = [:]

        for keyCode: CGKeyCode in 0 ..< 128 {
            guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
                continue
            }
            cgEvent.flags = []
            guard let nsEvent = NSEvent(cgEvent: cgEvent) else {
                continue
            }
            guard nsEvent.type == .keyDown else {
                continue
            }
            guard let characters = nsEvent.characters, characters.count == 1 else {
                continue
            }
            guard newMapping[characters] == nil else {
                continue
            }
            newMapping[characters] = keyCode
        }

        newMapping[Key.enter.rawValue] = 0x24
        newMapping[Key.tab.rawValue] = 0x30
        newMapping[Key.space.rawValue] = 0x31
        newMapping[Key.delete.rawValue] = 0x33
        newMapping[Key.escape.rawValue] = 0x35
        newMapping[Key.command.rawValue] = 0x37
        newMapping[Key.shift.rawValue] = 0x38
        newMapping[Key.capsLock.rawValue] = 0x39
        newMapping[Key.option.rawValue] = 0x3A
        newMapping[Key.control.rawValue] = 0x3B
        newMapping[Key.shiftRight.rawValue] = 0x3C
        newMapping[Key.optionRight.rawValue] = 0x3D
        newMapping[Key.controlRight.rawValue] = 0x3E
        newMapping[Key.arrowLeft.rawValue] = 0x7B
        newMapping[Key.arrowRight.rawValue] = 0x7C
        newMapping[Key.arrowDown.rawValue] = 0x7D
        newMapping[Key.arrowUp.rawValue] = 0x7E
        newMapping[Key.home.rawValue] = 0x73
        newMapping[Key.pageUp.rawValue] = 0x74
        newMapping[Key.backspace.rawValue] = 0x75
        newMapping[Key.end.rawValue] = 0x77
        newMapping[Key.pageDown.rawValue] = 0x79
        newMapping[Key.f1.rawValue] = 0x7A
        newMapping[Key.f2.rawValue] = 0x78
        newMapping[Key.f3.rawValue] = 0x63
        newMapping[Key.f4.rawValue] = 0x76
        newMapping[Key.f5.rawValue] = 0x60
        newMapping[Key.f6.rawValue] = 0x61
        newMapping[Key.f7.rawValue] = 0x62
        newMapping[Key.f8.rawValue] = 0x64
        newMapping[Key.f9.rawValue] = 0x65
        newMapping[Key.f10.rawValue] = 0x6D
        newMapping[Key.f11.rawValue] = 0x67
        newMapping[Key.f12.rawValue] = 0x6F
        for (keyString, keyCode) in newMapping {
            guard let key = Key(rawValue: keyString) else {
                continue
            }
            newReversedMapping[keyCode] = key
        }
        // As the keyCode of command and the keyCode of commandRight
        // are the same, avoid inserting commandRight into the reversed
        // mapping.
        newMapping[Key.commandRight.rawValue] = 0x37

        mapping = newMapping
        reversedMapping = newReversedMapping
    }

    public func keyCode(for key: Key) -> CGKeyCode? { mapping[key.rawValue] }

    public func key(from keyCode: CGKeyCode) -> Key? { reversedMapping[keyCode] }
}
