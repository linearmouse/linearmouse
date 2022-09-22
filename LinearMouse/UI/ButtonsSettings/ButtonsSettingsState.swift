// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

class ButtonsSettingsState: SchemeState {}

extension ButtonsSettingsState {
    var universalBackForward: Bool {
        get {
            guard let universalBackForward = scheme.buttons?.universalBackForward else {
                return false
            }

            return universalBackForward != .none
        }
        set {
            let universalBackForward: Scheme.Buttons.UniversalBackForward = newValue ? .both : .none

            Scheme(
                buttons: Scheme.Buttons(
                    universalBackForward: universalBackForward
                )
            )
            .merge(into: &scheme)
        }
    }
}
