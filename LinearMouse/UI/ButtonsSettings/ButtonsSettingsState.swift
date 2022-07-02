// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

class ButtonsSettingsState: SchemeState {}

extension ButtonsSettingsState {
    var universalBackForward: Bool {
        get {
            scheme.buttons?.universalBackForward ?? false
        }
        set {
            Scheme(
                buttons: Scheme.Buttons(
                    universalBackForward: newValue
                )
            )
            .merge(into: &scheme)
        }
    }
}
