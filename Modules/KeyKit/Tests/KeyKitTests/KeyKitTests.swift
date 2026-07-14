// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Carbon
@testable import KeyKit
import XCTest

final class KeyKitTests: XCTestCase {
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

    func testKeyCodeResolverUsesCommandLayerForRussianLayout() throws {
        let russianMapping = try characterMapping(inputSourceID: "com.apple.keylayout.Russian")
        let russianCommandMapping = try characterMapping(
            inputSourceID: "com.apple.keylayout.Russian",
            modifierKeyState: UInt32(cmdKey >> 8)
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

        XCTAssertNil(resolver.keyCode(for: .c))
        XCTAssertNil(resolver.keyCode(for: .v))
        XCTAssertEqual(resolver.keyCode(for: .c, modifiers: .maskCommand), 0x08)
        XCTAssertEqual(resolver.keyCode(for: .v, modifiers: .maskCommand), 0x09)
    }

    func testKeyCodeResolverDoesNotForceANSIPositionForDvorak() throws {
        let dvorakMapping = try characterMapping(inputSourceID: "com.apple.keylayout.Dvorak")
        let dvorakCommandMapping = try characterMapping(
            inputSourceID: "com.apple.keylayout.Dvorak",
            modifierKeyState: UInt32(cmdKey >> 8)
        )
        let ansiFallback = [Key.v.rawValue: CGKeyCode(kVK_ANSI_V)]
        let resolver = KeyCodeResolver { commandModified in
            commandModified ? [dvorakCommandMapping, dvorakMapping, ansiFallback] : [dvorakMapping]
        }

        XCTAssertEqual(resolver.keyCode(for: .v, modifiers: .maskCommand), 0x2F)
        XCTAssertNotEqual(resolver.keyCode(for: .v, modifiers: .maskCommand), CGKeyCode(kVK_ANSI_V))
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
