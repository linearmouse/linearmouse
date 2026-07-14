// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Carbon
import Combine
import CoreGraphics
import Foundation

/// Keyboard layout-independent key code resolver.
public class KeyCodeResolver {
    typealias CharacterMapping = [String: CGKeyCode]

    private var subscriptions = Set<AnyCancellable>()
    private let characterMappingsProvider: (_ commandModified: Bool) -> [CharacterMapping]
    private let mappingLock = NSLock()
    private var mapping: CharacterMapping = [:]
    private var commandMapping: CharacterMapping = [:]
    private var reversedMapping: [CGKeyCode: Key] = [:]

    public init() {
        characterMappingsProvider = { commandModified in
            Self.currentCharacterMappings(commandModified: commandModified)
        }

        startObservingInputSourceChanges()
        initializeMapping()
    }

    init(characterMappingsProvider: @escaping (_ commandModified: Bool) -> [CharacterMapping]) {
        self.characterMappingsProvider = characterMappingsProvider
        initializeMapping()
    }

    private func startObservingInputSourceChanges() {
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
    }

    private func initializeMapping() {
        // Text Input Source Services is not thread-safe.
        if Thread.isMainThread {
            updateMapping()
        } else {
            DispatchQueue.main.sync { updateMapping() }
        }
    }

    private func scheduleMappingUpdate(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.updateMapping()
        }
    }

    private func updateMapping() {
        var newMapping = Self.mergeCharacterMappings(characterMappingsProvider(false))
        var newCommandMapping = Self.mergeCharacterMappings(characterMappingsProvider(true))
        var newReversedMapping: [CGKeyCode: Key] = [:]

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
        newMapping[Key.f13.rawValue] = 0x69
        newMapping[Key.f14.rawValue] = 0x6B
        newMapping[Key.f15.rawValue] = 0x71
        newMapping[Key.f16.rawValue] = 0x6A
        newMapping[Key.f17.rawValue] = 0x40
        newMapping[Key.f18.rawValue] = 0x4F
        newMapping[Key.f19.rawValue] = 0x50
        newMapping[Key.f20.rawValue] = 0x5A
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

        // Command-modified characters from the active layout take priority. The regular
        // mapping fills layout-independent keys and any characters without a Command variant.
        newCommandMapping = Self.mergeCharacterMappings([newCommandMapping, newMapping])

        for (keyString, keyCode) in newMapping {
            guard let key = Key(rawValue: keyString) else {
                continue
            }
            newReversedMapping[keyCode] = key
        }

        mappingLock.withLock {
            mapping = newMapping
            commandMapping = newCommandMapping
            reversedMapping = newReversedMapping
        }
    }

    private static func currentCharacterMappings(commandModified: Bool) -> [CharacterMapping] {
        guard let currentInputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return []
        }

        let currentMapping = characterMapping(for: currentInputSource)
        guard commandModified else {
            return [currentMapping]
        }

        let commandModifierState = UInt32(cmdKey >> 8)
        let currentCommandMapping = characterMapping(
            for: currentInputSource,
            modifierKeyState: commandModifierState
        )
        var mappings = [currentCommandMapping, currentMapping]

        if let asciiInputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
            mappings.append(characterMapping(for: asciiInputSource))
        }

        return mappings
    }

    static func characterMapping(
        for inputSource: TISInputSource,
        modifierKeyState: UInt32 = 0
    ) -> CharacterMapping {
        guard let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return [:]
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else {
            return [:]
        }

        let keyboardType = UInt32(LMGetKbdType())
        var mapping: CharacterMapping = [:]

        for keyCode: CGKeyCode in 0 ..< 128 {
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)

            let status = layoutBytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
                UCKeyTranslate(
                    keyboardLayout,
                    keyCode,
                    UInt16(kUCKeyActionDown),
                    modifierKeyState,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
            }

            guard status == noErr, length == 1 else {
                continue
            }

            let character = String(utf16CodeUnits: characters, count: length)
            if mapping[character] == nil {
                mapping[character] = keyCode
            }
        }

        return mapping
    }

    static func mergeCharacterMappings(_ mappings: [CharacterMapping]) -> CharacterMapping {
        var result: CharacterMapping = [:]

        for mapping in mappings {
            for (character, keyCode) in mapping where result[character] == nil {
                result[character] = keyCode
            }
        }

        return result
    }

    public func keyCode(for key: Key, modifiers: CGEventFlags = []) -> CGKeyCode? {
        mappingLock.withLock {
            if modifiers.contains(.maskCommand) {
                return commandMapping[key.rawValue]
            }
            return mapping[key.rawValue]
        }
    }

    public func key(from keyCode: CGKeyCode) -> Key? {
        mappingLock.withLock { reversedMapping[keyCode] }
    }
}
