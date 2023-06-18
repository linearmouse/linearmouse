// MIT License
// Copyright (c) 2021-2023 LinearMouse

import AppKit
import Carbon
import Combine
import Foundation

/// Keyboard layout-independent key code resolver.
class KeyCodeResolver {
    private var subscriptions = Set<AnyCancellable>()
    private var mapping: [String: CGKeyCode] = [:]

    init() {
        DistributedNotificationCenter.default
            .publisher(for: .init(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
            .sink { [weak self] _ in
                self?.updateMapping()
            }
            .store(in: &subscriptions)

        DistributedNotificationCenter.default
            .publisher(for: .init(kTISNotifySelectedKeyboardInputSourceChanged as String))
            .sink { [weak self] _ in
                self?.updateMapping()
            }
            .store(in: &subscriptions)

        updateMapping()
    }

    private func updateMapping() {
        var newMapping: [String: CGKeyCode] = [:]

        for keyCode: CGKeyCode in 0 ..< 128 {
            guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
                continue
            }
            guard let nsEvent = NSEvent(cgEvent: cgEvent) else {
                continue
            }
            guard nsEvent.type == .keyDown else {
                continue
            }
            guard let characters = nsEvent.characters, characters.count == 1 else {
                continue
            }
            newMapping[characters] = keyCode
        }

        mapping = newMapping
    }

    // swiftlint:disable cyclomatic_complexity
    func keyCode(for key: Key) -> CGKeyCode? {
        switch key {
        case .enter: return 0x4C
        case .tab: return 0x30
        case .space: return 0x31
        case .delete: return 0x33
        case .escape: return 0x35
        case .command, .commandRight: return 0x37
        case .shift: return 0x38
        case .capsLock: return 0x39
        case .option: return 0x3A
        case .control: return 0x3B
        case .shiftRight: return 0x3C
        case .optionRight: return 0x3D
        case .controlRight: return 0x3E
        case .arrowLeft: return 0x7B
        case .arrowRight: return 0x7C
        case .arrowDown: return 0x7D
        case .arrowUp: return 0x7E
        case .home: return 0x73
        case .pageUp: return 0x74
        case .backspace: return 0x75
        case .end: return 0x77
        case .pageDown: return 0x79
        case .f1: return 0x7A
        case .f2: return 0x78
        case .f3: return 0x63
        case .f4: return 0x76
        case .f5: return 0x60
        case .f6: return 0x61
        case .f7: return 0x62
        case .f8: return 0x64
        case .f9: return 0x65
        case .f10: return 0x6D
        case .f11: return 0x67
        case .f12: return 0x6F
        default: return mapping[key.rawValue]
        }
    }
}
