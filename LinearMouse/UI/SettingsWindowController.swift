// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Combine
import Foundation
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var windowCoordinator: WindowCoordinator?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        super.init(window: nil)
        setupAppStateManager()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAppStateManager()
    }

    private func setupAppStateManager() {
        // Initialize app state manager to handle dock behavior
        _ = AppStateManager.shared
    }

    private func initWindowIfNeeded() {
        guard window == nil else {
            return
        }

        windowCoordinator = WindowCoordinator()
        windowCoordinator?.delegate = self

        let newWindow = windowCoordinator!.createWindow()
        window = newWindow
    }

    func bringToFront() {
        initWindowIfNeeded()
        window?.bringToFront()
    }
}

// MARK: - WindowCoordinatorDelegate

extension SettingsWindowController: WindowCoordinatorDelegate {
    func windowCoordinatorDidRequestClose(_: WindowCoordinator) {
        // Handle dock behavior when window closes
        AppStateManager.shared.handleWindowClosed()

        // Reset the window reference so it can be recreated
        window = nil
        windowCoordinator = nil
        cancellables.removeAll()
    }
}
