//
//  CheckForUpdatesButton.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/1/11.
//

import Combine
import SwiftUI
import Sparkle

final class UpdaterViewModel: ObservableObject {
    static let shared = UpdaterViewModel()

    @Published var canCheckForUpdates = false

    private let controller = AutoUpdateManager.shared.controller
    private var subscription: AnyCancellable! = nil

    init() {
        subscription = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { value in
                self.canCheckForUpdates = value
            }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updaterViewModel = UpdaterViewModel.shared

    var body: some View {
        Button("Check for Updates...", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
