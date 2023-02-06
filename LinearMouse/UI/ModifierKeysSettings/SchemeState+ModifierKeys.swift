// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension SchemeState {
    var commandAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling.modifiers.command
        }

        set {
            scheme.scrolling.modifiers.command = newValue
        }
    }

    var shiftAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling.modifiers.shift
        }

        set {
            scheme.scrolling.modifiers.shift = newValue
        }
    }

    var optionAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling.modifiers.option
        }

        set {
            scheme.scrolling.modifiers.option = newValue
        }
    }

    var controlAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling.modifiers.control
        }

        set {
            scheme.scrolling.modifiers.control = newValue
        }
    }
}
