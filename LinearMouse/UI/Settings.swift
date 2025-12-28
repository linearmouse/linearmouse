// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Combine
import Defaults
import SwiftUI

struct Settings: View {
    @ObservedObject var state = SettingsState.shared

    @State private var showInDockTask: Task<Void, Never>?

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
        .onAppear {
            showInDockTask = Task {
                for await value in Defaults.updates(.showInDock, initial: true) {
                    if value {
                        NSApplication.shared.setActivationPolicy(.regular)
                    } else {
                        NSApplication.shared.setActivationPolicy(.accessory)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }

                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
        .onDisappear {
            if let showInDockTask {
                showInDockTask.cancel()
                self.showInDockTask = nil
            }
        }
    }
}
