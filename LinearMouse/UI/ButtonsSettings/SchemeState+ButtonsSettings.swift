// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension SchemeState {
    var universalBackForward: Bool {
        get {
            scheme.buttons?.universalBackForward ?? .none != .none
        }
        set {
            Scheme(
                buttons: Scheme.Buttons(
                    universalBackForward: .some(newValue ? .both : .none)
                )
            )
            .merge(into: &scheme)
        }
    }
}
