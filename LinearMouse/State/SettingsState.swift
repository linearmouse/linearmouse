// MIT License
// Copyright (c) 2021-2026 LinearMouse

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

    /// Set to `true` by `LogitechReprogrammableControlsMonitor` after all controls are diverted during recording.
    /// The button recorder waits for this before showing the recording UI to prevent the user
    /// from pressing a button before diversion is active.
    @Published var recordingDivertReady = false

    /// Set by protocol-backed button monitors when a virtual button is pressed during recording.
    /// The button recorder observes this to capture non-CGEvent button identity without synthetic events.
    @Published var recordedButton: Scheme.Buttons.Mapping.Button?
}
