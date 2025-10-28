// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

class SettingsState: ObservableObject {
    static let shared = SettingsState()

    enum Navigation {
        case scrolling, pointer, buttons, general
    }

    @Published var navigation: Navigation? = .pointer

    /// When `recording` is true, `ButtonActionsTransformer` should be temporarily disabled.
    @Published var recording = false
}
