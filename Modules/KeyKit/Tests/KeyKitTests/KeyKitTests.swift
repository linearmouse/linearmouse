// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Carbon
@testable import KeyKit
import XCTest

final class KeyKitTests: XCTestCase {
    private static let commonShortcutKeys: [(Key, CGKeyCode)] = [
        (.a, CGKeyCode(kVK_ANSI_A)),
        (.c, CGKeyCode(kVK_ANSI_C)),
        (.e, CGKeyCode(kVK_ANSI_E)),
        (.k, CGKeyCode(kVK_ANSI_K)),
        (.u, CGKeyCode(kVK_ANSI_U)),
        (.v, CGKeyCode(kVK_ANSI_V)),
        (.w, CGKeyCode(kVK_ANSI_W)),
        (.x, CGKeyCode(kVK_ANSI_X)),
        (.z, CGKeyCode(kVK_ANSI_Z))
    ]

    private static let nonCommandModifierSets: [CGEventFlags] = [
        .maskShift,
        .maskAlternate,
        .maskControl,
        [.maskControl, .maskShift],
        [.maskAlternate, .maskShift],
        [.maskControl, .maskAlternate]
    ]

    private static let commandModifierSets: [CGEventFlags] = [
        .maskCommand,
        [.maskCommand, .maskShift],
        [.maskCommand, .maskAlternate],
        [.maskCommand, .maskControl],
        [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    ]

    private func characterMapping(
        inputSourceID: String,
        modifierKeyState: UInt32 = 0
    ) throws -> KeyCodeResolver.CharacterMapping {
        let filter = [kTISPropertyInputSourceID!: inputSourceID as CFString] as CFDictionary
        let inputSources = try XCTUnwrap(
            TISCreateInputSourceList(filter, true).takeRetainedValue() as? [TISInputSource]
        )
        let inputSource = try XCTUnwrap(inputSources.first)
        return KeyCodeResolver.characterMapping(
            for: inputSource,
            modifierKeyState: modifierKeyState
        )
    }

    /// The tests below post real keyboard / system-defined events into the OS, which causes
    /// observable side effects (volume change, Mission Control space switch, stuck modifier
    /// state in WindowServer, etc.). Gate them behind an env var so day-to-day `swift test`
    /// stays side-effect free; CI can opt in by setting `RUN_INTEGRATION_TESTS=1`.
    private func skipUnlessIntegrationEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run KeyKit integration tests that post real system events."
        )
    }

    func testKeySimulatorInitializesOffMainThread() {
        let expectation = expectation(description: "Initialize KeySimulator off the main thread")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = KeySimulator()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
    }

    func testKeyCodeResolverSupportsCommonModifierShortcutsInRussianLayout() throws {
        let russianMapping = try characterMapping(inputSourceID: "com.apple.keylayout.Russian")
        let russianCommandMapping = try characterMapping(
            inputSourceID: "com.apple.keylayout.Russian",
            modifierKeyState: UInt32(cmdKey >> 8)
        )
        let russianControlMapping = try characterMapping(
            inputSourceID: "com.apple.keylayout.Russian",
            modifierKeyState: UInt32(controlKey >> 8)
        )

        XCTAssertNil(russianMapping[Key.c.rawValue])
        XCTAssertNil(russianMapping[Key.v.rawValue])
        XCTAssertEqual(russianMapping["с"], 0x08)
        XCTAssertEqual(russianMapping["м"], 0x09)
        XCTAssertEqual(russianCommandMapping[Key.c.rawValue], 0x08)
        XCTAssertEqual(russianCommandMapping[Key.v.rawValue], 0x09)

        let resolver = KeyCodeResolver { commandModified in
            commandModified ? [russianCommandMapping, russianMapping] : [russianMapping]
        }

        for (key, ansiKeyCode) in Self.commonShortcutKeys {
            XCTAssertEqual(resolver.key(from: ansiKeyCode), key)

            for modifiers in Self.nonCommandModifierSets {
                XCTAssertEqual(resolver.keyCode(for: key, modifiers: modifiers), ansiKeyCode)
            }
            for modifiers in Self.commandModifierSets {
                XCTAssertEqual(resolver.keyCode(for: key, modifiers: modifiers), ansiKeyCode)
            }

            let asciiValue = try XCTUnwrap(key.rawValue.utf8.first)
            let controlCharacter = String(UnicodeScalar(asciiValue & 0x1F))
            XCTAssertEqual(russianControlMapping[controlCharacter], ansiKeyCode)
        }
    }

    func testANSICharacterMappingMatchesBuiltInUSLayout() throws {
        let usMapping = try characterMapping(inputSourceID: "com.apple.keylayout.US")

        XCTAssertEqual(KeyCodeResolver.ansiCharacterMapping.count, 47)
        for (character, keyCode) in KeyCodeResolver.ansiCharacterMapping {
            XCTAssertEqual(usMapping[character], keyCode)
        }
    }

    func testKeyCodeResolverDoesNotForceANSIPositionForDvorak() throws {
        let dvorakMapping = try characterMapping(inputSourceID: "com.apple.keylayout.Dvorak")
        let dvorakCommandMapping = try characterMapping(
            inputSourceID: "com.apple.keylayout.Dvorak",
            modifierKeyState: UInt32(cmdKey >> 8)
        )
        let resolver = KeyCodeResolver { commandModified in
            commandModified ? [dvorakCommandMapping, dvorakMapping] : [dvorakMapping]
        }

        let modifierSets: [CGEventFlags] = [
            .maskShift,
            .maskAlternate,
            .maskControl,
            .maskCommand,
            [.maskCommand, .maskShift],
            [.maskCommand, .maskAlternate],
            [.maskCommand, .maskControl]
        ]

        for modifiers in modifierSets {
            XCTAssertEqual(resolver.keyCode(for: .v, modifiers: modifiers), 0x2F)
            XCTAssertNotEqual(resolver.keyCode(for: .v, modifiers: modifiers), CGKeyCode(kVK_ANSI_V))
        }
        XCTAssertEqual(resolver.key(from: 0x2F), .v)
    }

    func testPressKey() throws {
        try skipUnlessIntegrationEnabled()
        let keySimulator = KeySimulator()
        try keySimulator.press(.home)
    }

    func testPostSymbolicHotKey() throws {
        try skipUnlessIntegrationEnabled()
        try postSymbolicHotKey(.spaceLeft)
    }

    func testPostSystemDefinedKey() throws {
        try skipUnlessIntegrationEnabled()
        postSystemDefinedKey(.soundDown)
    }
}
