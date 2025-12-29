// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation
import SwiftUI

class SettingsState: ObservableObject {
    static let shared = SettingsState()

    enum Navigation: String, CaseIterable, Hashable {
        case pointer, scrolling, buttons, general

        var title: LocalizedStringKey {
            switch self {
            case .pointer:
                return "Pointer"
            case .scrolling:
                return "Scrolling"
            case .buttons:
                return "Buttons"
            case .general:
                return "General"
            }
        }

        var imageName: String {
            switch self {
            case .pointer:
                return "Pointer"
            case .scrolling:
                return "Scrolling"
            case .buttons:
                return "Buttons"
            case .general:
                return "General"
            }
        }
    }

    @Published var navigation: Navigation? = .pointer

    /// When `recording` is true, `ButtonActionsTransformer` should be temporarily disabled.
    @Published var recording = false
}
