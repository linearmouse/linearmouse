// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation
import PublishedObject

class ButtonsSettingsState: ObservableObject {
    static let shared: ButtonsSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    var scheme: Scheme {
        get { schemeState.scheme }
        set { schemeState.scheme = newValue }
    }
}

extension ButtonsSettingsState {
    var universalBackForward: Bool {
        get {
            scheme.buttons.universalBackForward ?? .none != .none
        }
        set {
            scheme.buttons.universalBackForward = .some(newValue ? .both : .none)
        }
    }
}
