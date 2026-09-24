// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Carbon
import Combine
@testable import KeyKit
import XCTest

final class KeyEquivalentResolverTests: XCTestCase {
    private typealias Shortcut = KeyEquivalentResolver.Shortcut

    func testAppKitResolvesCurrentLayoutWithoutChangingInputSource() throws {
        guard #available(macOS 12, *) else {
            throw XCTSkip("Automatic key equivalent localization requires macOS 12")
        }
        _ = NSApplication.shared
        let before = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let shortcuts = KeyEquivalentResolver.resolve(keyEquivalents: ["+", "-"])
        XCTAssertNotNil(shortcuts["+"])
        XCTAssertNotNil(shortcuts["-"])
        XCTAssertNotEqual(shortcuts["+"], shortcuts["-"])
        XCTAssertEqual(before, TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    func testReservedSystemShortcutIsSkippedEvenIfAppKitMatchesIt() {
        let screenshot = Shortcut(keyCode: CGKeyCode(kVK_ANSI_3), modifierFlags: [.maskCommand, .maskShift])
        let zoomIn = Shortcut(keyCode: CGKeyCode(kVK_ANSI_Equal), modifierFlags: [.maskCommand, .maskShift])
        let zoomOut = Shortcut(keyCode: CGKeyCode(kVK_ANSI_Minus), modifierFlags: .maskCommand)
        var candidates: [Shortcut] = []
        let result = KeyEquivalentResolver.resolve(keyEquivalents: ["+", "-"], reserved: [screenshot]) { shortcut in
            candidates.append(shortcut)
            if shortcut == screenshot || shortcut == zoomIn {
                return "+"
            }
            if shortcut == zoomOut {
                return "-"
            }
            return nil
        }
        XCTAssertEqual(result, ["+": zoomIn, "-": zoomOut])
        XCTAssertFalse(candidates.contains(screenshot))
    }

    func testUnresolvableShortcutDoesNotInventAnANSIFallback() {
        let result = KeyEquivalentResolver.resolve(keyEquivalents: ["+", "-"], reserved: []) { _ in nil }
        XCTAssertTrue(result.isEmpty)
    }

    func testSystemHotKeysUseCarbonModifiersAndIgnoreDisabledEntries() {
        let entry: [String: Any] = [
            kHISymbolicHotKeyEnabled as String: true,
            kHISymbolicHotKeyCode as String: NSNumber(value: kVK_ANSI_3),
            kHISymbolicHotKeyModifiers as String: NSNumber(value: cmdKey | shiftKey)
        ]
        var disabled = entry
        disabled[kHISymbolicHotKeyEnabled as String] = false
        XCTAssertEqual(KeyEquivalentResolver.reservedShortcuts(in: [entry, disabled, [:]]), [
            .init(keyCode: CGKeyCode(kVK_ANSI_3), modifierFlags: [.maskCommand, .maskShift])
        ])
    }

    func testCachedReadsDoNotResolveOnTheEventThread() {
        var resolutions = 0
        let zoomIn = Shortcut(keyCode: 24, modifierFlags: [.maskCommand, .maskShift])
        let resolver = KeyEquivalentResolver(resolve: {
            XCTAssertTrue(Thread.isMainThread)
            resolutions += 1
            return ["+": zoomIn]
        }, inputSourceChanges: Empty().eraseToAnyPublisher())
        resolver.refresh()

        let read = expectation(description: "Read shortcuts from the event thread")
        DispatchQueue.global().async {
            for _ in 0 ..< 100 {
                XCTAssertEqual(resolver.shortcut(for: "+"), zoomIn)
            }
            read.fulfill()
        }
        wait(for: [read], timeout: 2)
        XCTAssertEqual(resolutions, 1)
    }

    func testInputSourceChangeInvalidatesThenRefreshesTheCacheOnMainThread() {
        let changes = PassthroughSubject<Void, Never>()
        var current = Shortcut(keyCode: 24, modifierFlags: [.maskCommand, .maskShift])
        let refreshed = expectation(description: "Rebuild shortcuts for the new layout")
        var resolutions = 0
        let resolver = KeyEquivalentResolver(resolve: {
            XCTAssertTrue(Thread.isMainThread)
            resolutions += 1
            if resolutions == 2 {
                refreshed.fulfill()
            }
            return ["+": current]
        }, inputSourceChanges: changes.eraseToAnyPublisher())
        resolver.refresh()
        XCTAssertEqual(resolver.shortcut(for: "+"), current)

        current = .init(keyCode: 30, modifierFlags: [.maskCommand, .maskShift])
        changes.send()
        changes.send()
        XCTAssertNil(resolver.shortcut(for: "+"))
        wait(for: [refreshed], timeout: 2)
        XCTAssertEqual(resolver.shortcut(for: "+"), current)
        XCTAssertEqual(resolutions, 2)
    }

    func testInputSourceChangeDuringResolutionDoesNotPublishStaleShortcuts() {
        let changes = PassthroughSubject<Void, Never>()
        let resolver = KeyEquivalentResolver(resolve: {
            changes.send()
            return ["+": .init(keyCode: 24, modifierFlags: [.maskCommand, .maskShift])]
        }, inputSourceChanges: changes.eraseToAnyPublisher())
        resolver.refresh()
        XCTAssertNil(resolver.shortcut(for: "+"))
    }
}
