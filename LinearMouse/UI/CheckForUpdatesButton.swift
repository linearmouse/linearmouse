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
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    @Published var updateCheckInterval: TimeInterval = 604800 {
        didSet {
            controller.updater.updateCheckInterval = updateCheckInterval
        }
    }

    private let controller = AutoUpdateManager.shared.controller
    private var canCheckForUpdatesSubscription: AnyCancellable! = nil
    private var automaticallyChecksForUpdatesSubscription: AnyCancellable! = nil
    private var updateCheckIntervalSubscription: AnyCancellable! = nil

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

struct CheckForUpdatesButton: View {
    @ObservedObject var updaterViewModel = UpdaterViewModel.shared

    var body: some View {
        Button("Check for Updates...", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
        HStack {
            Toggle(isOn: $updaterViewModel.automaticallyChecksForUpdates) {
                Text("Automatically")
            }
            Picker("", selection: $updaterViewModel.updateCheckInterval) {
                Text("Daily").tag(TimeInterval(86400))
                Text("Weekly").tag(TimeInterval(604800))
                Text("Monthly").tag(TimeInterval(2629800))
            }
            .frame(width: 120)
            .disabled(!updaterViewModel.automaticallyChecksForUpdates)
        }
        .controlSize(.small)
    }
}
