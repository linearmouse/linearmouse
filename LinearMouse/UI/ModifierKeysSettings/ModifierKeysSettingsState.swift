// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation
import PublishedObject

class ModifierKeysSettingsState: ObservableObject {
    static let shared: ModifierKeysSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    var scheme: Scheme {
        get { schemeState.scheme }
        set { schemeState.scheme = newValue }
    }
}

extension ModifierKeysSettingsState {
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
