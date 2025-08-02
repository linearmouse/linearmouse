// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine
import Defaults
import Foundation

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()

    private var showInDockTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    deinit {
        showInDockTask?.cancel()
    }

    func setupDockBehavior() {
        showInDockTask?.cancel()

        showInDockTask = Task {
            for await value in Defaults.updates(.showInDock, initial: true) {
                await MainActor.run {
                    if value {
                        NSApplication.shared.setActivationPolicy(.regular)
                    } else {
                        NSApplication.shared.setActivationPolicy(.accessory)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
    }

    func handleWindowClosed() {
        // When settings window is closed, always return to accessory mode
        // This matches the original behavior where onDisappear would cancel the task
        // and the task's final line would set activation policy to accessory
        Task {
            await MainActor.run {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    func cleanup() {
        showInDockTask?.cancel()
        showInDockTask = nil
        cancellables.removeAll()
    }
}
