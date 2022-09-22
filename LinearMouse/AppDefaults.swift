// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

class AppDefaults: ObservableObject {
    public static let shared = AppDefaults()

    @AppStorageCompat("reverseScrollingOn") var reverseScrollingVerticallyOn = true {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("reverseScrollingHorizontallyOn") var reverseScrollingHorizontallyOn = false {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("linearScrollingOn") var linearScrollingOn = false {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("scrollLines") var scrollLines = 3 {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("universalBackForwardOn") var universalBackForwardOn = true {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("showInMenuBar") var showInMenuBar = true {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("betaChannelOn") var betaChannelOn = false {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("linearMovementOn") var linearMovementOn = false {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("cursor.acceleration") var cursorAcceleration = 0.6875 {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("cursor.sensitivity") var cursorSensitivity = 1600.0 {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("modifiers.command.action") var modifiersCommandAction = ModifierKeyAction(type: .noAction,
                                                                                                 speedFactor: 5.0) {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("modifiers.shift.action") var modifiersShiftAction = ModifierKeyAction(type: .noAction,
                                                                                             speedFactor: 2.0) {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("modifiers.alternate.action") var modifiersAlternateAction = ModifierKeyAction(type: .noAction,
                                                                                                     speedFactor: 1.0) {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat("modifiers.control.action") var modifiersControlAction = ModifierKeyAction(type: .noAction,
                                                                                                 speedFactor: 0.2) {
        willSet {
            objectWillChange.send()
        }
    }
}
