// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import Sparkle
import SwiftUI

final class UpdaterViewModel: ObservableObject {
    static let shared = UpdaterViewModel()

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @Published var updateCheckInterval: TimeInterval = 604_800 {
        didSet {
            controller.updater.updateCheckInterval = updateCheckInterval
        }
    }

    private let controller = AutoUpdateManager.shared.controller
    private var canCheckForUpdatesSubscription: AnyCancellable!
    private var automaticallyChecksForUpdatesSubscription: AnyCancellable!
    private var updateCheckIntervalSubscription: AnyCancellable!

    init() {
        canCheckForUpdatesSubscription = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { value in
                self.canCheckForUpdates = value
            }
        automaticallyChecksForUpdatesSubscription = controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { value in
                guard value != self.automaticallyChecksForUpdates else {
                    return
                }
                self.automaticallyChecksForUpdates = value
            }
        updateCheckIntervalSubscription = controller.updater.publisher(for: \.updateCheckInterval)
            .sink { value in
                guard value != self.updateCheckInterval else {
                    return
                }
                self.updateCheckInterval = value
            }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel = UpdaterViewModel.shared
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Version: \(LinearMouse.appVersion)")
                .foregroundColor(.secondary)
            HStack {
                Button("Check for Updates...", action: updaterViewModel.checkForUpdates)
                    .disabled(!updaterViewModel.canCheckForUpdates)
            }
            HStack {
                Toggle(isOn: $updaterViewModel.automaticallyChecksForUpdates) {
                    Text("Automatically")
                }
                Picker("", selection: $updaterViewModel.updateCheckInterval) {
                    Text("Daily").tag(TimeInterval(86400))
                    Text("Weekly").tag(TimeInterval(604_800))
                    Text("Monthly").tag(TimeInterval(2_629_800))
                }
                .frame(width: 120)
                .disabled(!updaterViewModel.automaticallyChecksForUpdates)
            }
            Toggle(isOn: $defaults.betaChannelOn) {
                Text("Include beta")
            }
        }
        .controlSize(.small)
    }
}
