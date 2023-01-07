// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import CoreFoundation
import KeyKitC

public enum SymbolicHotKey: UInt32 {
    // full keyboard access hotkeys
    case toggleFullKeyboardAccess = 12,
         focusMenubar = 7,
         focusDock = 8,
         focusNextGlobalWindow = 9,
         focusToolbar = 10,
         focusFloatingWindow = 11,
         focusApplicationWindow = 27,
         focusNextControl = 13,
         focusDrawer = 51,
         focusStatusItems = 57,

         // screenshot hotkeys
         screenshot = 28,
         screenshotToClipboard = 29,
         screenshotRegion = 30,
         screenshotRegionToClipboard = 31,

         // universal access
         toggleZoom = 15,
         zoomOut = 19,
         zoomIn = 17,
         zoomToggleSmoothing = 23,
         increaseContrast = 25,
         decreaseContrast = 26,
         invertScreen = 21,
         toggleVoiceOver = 59,

         // Dock
         toggleDockAutohide = 52,
         exposeAllWindows = 32,
         exposeAllWindowsSlow = 34,
         exposeApplicationWindows = 33,
         exposeApplicationWindowsSlow = 35,
         exposeDesktop = 36,
         exposeDesktopsSlow = 37,
         dashboard = 62,
         dashboardSlow = 63,

         // spaces (Leopard and later)
         spaces = 75,
         spacesSlow = 76,
         // 77 - fn F7 (disabled)
         // 78 - ⇧fn F7 (disabled)
         spaceLeft = 79,
         spaceLeftSlow = 80,
         spaceRight = 81,
         spaceRightSlow = 82,
         spaceDown = 83,
         spaceDownSlow = 84,
         spaceUp = 85,
         spaceUpSlow = 86,

         // input
         toggleCharacterPallette = 50,
         selectPreviousInputSource = 60,
         selectNextInputSource = 61,

         // Spotlight
         spotlightSearchField = 64,
         spotlightWindow = 65,

         toggleFrontRow = 73,
         lookUpWordInDictionary = 70,
         help = 98,

         // displays - not verified
         decreaseDisplayBrightness = 53,
         increaseDisplayBrightness = 54
}

public enum CGSError: Error {
    case CoreGraphicsError(CGError)
}

public func postSymbolicHotKey(_ hotkey: SymbolicHotKey) throws {
    let hotkey = CGSSymbolicHotKey(hotkey.rawValue)

    var keyEquivalent: unichar = 0
    var virtualKeyCode: unichar = 0
    var modifiers = CGSModifierFlags(0)

    let error = CGSGetSymbolicHotKeyValue(
        hotkey,
        &keyEquivalent,
        &virtualKeyCode,
        &modifiers
    )
    guard error == .success else {
        throw CGSError.CoreGraphicsError(error)
    }

    let hotkeyEnabled = CGSIsSymbolicHotKeyEnabled(hotkey)
    if !hotkeyEnabled {
        CGSSetSymbolicHotKeyEnabled(hotkey, true)
    }
    defer {
        if !hotkeyEnabled {
            waitUntilCGEventsBeingHandled()
            CGSSetSymbolicHotKeyEnabled(hotkey, false)
        }
    }

    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKeyCode, keyDown: true)!
    keyDown.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKeyCode, keyDown: false)!
    keyUp.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))

    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)
}

private func waitUntilCGEventsBeingHandled() {
    enum Consts {
        static let magic: Int64 = 10086
    }

    var seenMark = false

    let callback: CGEventTapCallBack = { _, _, event, refcon in
        if event.getIntegerValueField(.eventSourceUserData) == Consts.magic {
            refcon?.storeBytes(of: true, as: Bool.self)
        }

        return Unmanaged.passUnretained(event)
    }

    let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                     place: .tailAppendEventTap,
                                     options: .listenOnly,
                                     eventsOfInterest: 1 << CGEventType.null.rawValue,
                                     callback: callback,
                                     userInfo: &seenMark)!

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

    let mark = CGEvent(source: nil)!
    mark.setIntegerValueField(.eventSourceUserData, value: Consts.magic)
    mark.post(tap: .cgSessionEventTap)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    for _ in 0 ..< 10 {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
        if seenMark {
            break
        }
    }

    CGEvent.tapEnable(tap: eventTap, enable: false)

    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
}
