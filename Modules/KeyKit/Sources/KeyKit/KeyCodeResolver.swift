// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Carbon
import Combine
import Foundation

/// Keyboard layout-independent key code resolver.
public class KeyCodeResolver {
    private var subscriptions = Set<AnyCancellable>()
    private let mappingLock = NSLock()
    private var mapping: [String: CGKeyCode] = [:]
    private var reversedMapping: [CGKeyCode: Key] = [:]

    public init() {
        DistributedNotificationCenter.default
            .publisher(for: .init(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
            .sink { [weak self] _ in
                self?.scheduleMappingUpdate(after: 0.1)
            }
            .store(in: &subscriptions)

        DistributedNotificationCenter.default
            .publisher(for: .init(kTISNotifySelectedKeyboardInputSourceChanged as String))
            .sink { [weak self] _ in
                self?.scheduleMappingUpdate(after: 0.1)
            }
            .store(in: &subscriptions)

        updateMapping()
    }

    private func scheduleMappingUpdate(after delay: TimeInterval) {
        // The TIS-source-changed notification fires before the new layout is fully published; a
        // small delay lets the new source settle before we re-translate.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.updateMapping()
        }
    }

    private func updateMapping() {
        var newMapping: [String: CGKeyCode] = [:]
        var newReversedMapping: [CGKeyCode: Key] = [:]

        for keyCode: CGKeyCode in 0 ..< 128 {
            guard let characters = translatedCharacters(for: keyCode), characters.count == 1 else {
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
        newMapping[Key.commandRight.rawValue] = 0x36
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
        newMapping[Key.numpadPlus.rawValue] = 0x45
        newMapping[Key.numpadMinus.rawValue] = 0x4E
        newMapping[Key.numpadMultiply.rawValue] = 0x43
        newMapping[Key.numpadDivide.rawValue] = 0x4B
        newMapping[Key.numpadEnter.rawValue] = 0x4C
        newMapping[Key.numpadEquals.rawValue] = 0x51
        newMapping[Key.numpadDecimal.rawValue] = 0x41
        newMapping[Key.numpadClear.rawValue] = 0x47
        newMapping[Key.numpad0.rawValue] = 0x52
        newMapping[Key.numpad1.rawValue] = 0x53
        newMapping[Key.numpad2.rawValue] = 0x54
        newMapping[Key.numpad3.rawValue] = 0x55
        newMapping[Key.numpad4.rawValue] = 0x56
        newMapping[Key.numpad5.rawValue] = 0x57
        newMapping[Key.numpad6.rawValue] = 0x58
        newMapping[Key.numpad7.rawValue] = 0x59
        newMapping[Key.numpad8.rawValue] = 0x5B
        newMapping[Key.numpad9.rawValue] = 0x5C
        for (keyString, keyCode) in newMapping {
            guard let key = Key(rawValue: keyString) else {
                continue
            }
            newReversedMapping[keyCode] = key
        }

        mappingLock.withLock {
            mapping = newMapping
            reversedMapping = newReversedMapping
        }
    }

    private func translatedCharacters(for keyCode: CGKeyCode) -> String? {
        guard let layoutData = currentKeyboardLayoutData(),
              let layoutBytes = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        let keyboardType = UInt32(LMGetKbdType())

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = layoutBytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
            UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else {
            return nil
        }

        // Layouts that uppercase-by-default (none in the standard ones, but defensive against
        // exotic third-party layouts) would otherwise miss the lowercase entries in `Key`.
        return String(utf16CodeUnits: chars, count: Int(length)).lowercased()
    }

    private func currentKeyboardLayoutData() -> CFData? {
        let sources: [Unmanaged<TISInputSource>?] = [
            TISCopyCurrentKeyboardLayoutInputSource(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()
        ]

        for source in sources {
            guard let source = source?.takeRetainedValue(),
                  let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                continue
            }

            return unsafeBitCast(layoutDataPointer, to: CFData.self)
        }

        return nil
    }

    public func keyCode(for key: Key) -> CGKeyCode? {
        mappingLock.withLock { mapping[key.rawValue] }
    }

    public func key(from keyCode: CGKeyCode) -> Key? {
        mappingLock.withLock { reversedMapping[keyCode] }
    }
}
