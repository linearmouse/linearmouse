// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import CGSKitC

enum SymbolicHotKey: UInt32 {
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

enum CGSError: Error {
    case CoreGraphicsError(CGError)
}

func postSymbolicHotKey(_ hotkey: SymbolicHotKey) throws {
    var keyEquivalent: unichar = 0
    var virtualKeyCode: unichar = 0
    var modifiers = CGSModifierFlags(0)

    let error = CGSGetSymbolicHotKeyValue(
        CGSSymbolicHotKey(hotkey.rawValue),
        &keyEquivalent,
        &virtualKeyCode,
        &modifiers
    )
    guard error == .success else {
        throw CGSError.CoreGraphicsError(error)
    }

    let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKeyCode, keyDown: true)!
    down.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKeyCode, keyDown: false)!
    up.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))

    down.post(tap: .cgSessionEventTap)
    up.post(tap: .cgSessionEventTap)
}
