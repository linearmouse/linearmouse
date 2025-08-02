// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

// Legacy Settings view - now replaced by AppKit-based implementation
// This is kept for backwards compatibility but is no longer used by default
struct Settings: View {
    @ObservedObject var state = SettingsState.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .padding(5)
                .frame(minWidth: 200, maxWidth: 200, maxHeight: .infinity, alignment: .top)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .edgesIgnoringSafeArea(.top)
                )

            if let navigation = state.navigation {
                switch navigation {
                case .scrolling:
                    ScrollingSettings()
                case .pointer:
                    PointerSettings()
                case .buttons:
                    ButtonsSettings()
                case .general:
                    GeneralSettings()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 600, alignment: .top)
    }
}
