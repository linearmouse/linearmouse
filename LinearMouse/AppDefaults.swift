// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

class AppDefaults: ObservableObject {
    public static let shared = AppDefaults()

    @AppStorageCompat(wrappedValue: true, "reverseScrollingOn") var reverseScrollingVerticallyOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: false, "reverseScrollingHorizontallyOn") var reverseScrollingHorizontallyOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: false, "linearScrollingOn") var linearScrollingOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: 3, "scrollLines") var scrollLines: Int {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: true, "universalBackForwardOn") var universalBackForwardOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: true, "showInMenuBar") var showInMenuBar: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: false, "betaChannelOn") var betaChannelOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: false, "linearMovementOn") var linearMovementOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: 0.6875, "cursor.acceleration") var cursorAcceleration: Double {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: 1600, "cursor.sensitivity") var cursorSensitivity: Double {
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
