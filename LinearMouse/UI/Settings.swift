// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import SwiftUI

struct Settings: View {
    @ObservedObject var state = SettingsState.shared

    var body: some View {
        HStack(spacing: 0) {
            if #available(macOS 11, *) {
                Sidebar()
            } else {
                // FIXME: Workaround for Catalina
                Sidebar()
                    .padding(.top)
            }

            if let navigation = state.navigation {
                switch navigation {
                case .scrolling:
                    ScrollingSettings()
                case .pointer:
                    PointerSettings()
                case .buttons:
                    ButtonsSettings()
                case .modifierKeys:
                    ModifierKeysSettings()
                case .general:
                    GeneralSettings()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 600)
    }
}
