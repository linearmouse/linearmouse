// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

class SettingsState: ObservableObject {
    static let shared = SettingsState()

    enum Navigation {
        case scrolling, pointer, buttons, modifierKeys, general
    }

    @Published var navigation: Navigation? = .scrolling
}
