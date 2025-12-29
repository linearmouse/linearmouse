// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Defaults
import SwiftUI

struct Settings: View {
    @State private var showInDockTask: Task<Void, Never>?

    var body: some View {
        EmptyView()
            .onAppear(perform: startShowInDockTask)
            .onDisappear(perform: stopShowInDockTask)
    }

    private func startShowInDockTask() {
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

    private func stopShowInDockTask() {
        showInDockTask?.cancel()
        showInDockTask = nil
    }
}
