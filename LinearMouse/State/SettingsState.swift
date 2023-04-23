// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation

class SettingsState: ObservableObject {
    static let shared = SettingsState()

    enum Navigation {
        case scrolling, pointer, buttons, general
    }

    @Published var navigation: Navigation? = .scrolling

    /// When `recording` is true, `ButtonActionsTransformer` should be temporarily disabled.
    @Published var recording = false
}
