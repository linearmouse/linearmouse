// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import AppKit
import Combine
import Defaults
import Foundation
import os.log
import SwiftUI

class ConfigurationState: ObservableObject {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    static let shared = ConfigurationState()

    let configurationPath = URL(
        fileURLWithPath: ".config/linearmouse/linearmouse.json",
        relativeTo: FileManager.default.homeDirectoryForCurrentUser
    )

    private var configurationSaveDebounceTimer: Timer?
    @Published var configuration = Configuration() {
        didSet {
            configurationSaveDebounceTimer?.invalidate()
            guard shouldAutoSaveConfiguration else {
                return
            }

            configurationSaveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2,
                                                                  repeats: false) { [weak self] _ in
                guard let self = self else {
                    return
                }

                os_log("Saving new configuration: %{public}@", log: Self.log, type: .debug,
                       String(describing: self.configuration))
                self.save()
            }
        }
    }

    private var shouldAutoSaveConfiguration = true

    private var subscriptions = Set<AnyCancellable>()
}

extension ConfigurationState {
    func load() {
        shouldAutoSaveConfiguration = false
        defer {
            shouldAutoSaveConfiguration = true
        }

        do {
            configuration = try Configuration.load(from: configurationPath)
        } catch CocoaError.fileReadNoSuchFile {
            os_log("No configuration file found, try creating a default one",
                   log: Self.log, type: .debug)
            save()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(
                format: NSLocalizedString("Failed to load the configuration: %@", comment: ""),
                error.localizedDescription
            )
            alert.runModal()
        }
    }

    func save() {
        do {
            try configuration.dump(to: configurationPath)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(
                format: NSLocalizedString("Failed to save the configuration: %@", comment: ""),
                error.localizedDescription
            )
            alert.runModal()
        }
    }

    func getSchemeIndex(forDevice device: Device, forApp app: String? = nil) -> Int? {
        configuration.schemes.firstIndex {
            guard $0.isDeviceSpecific else {
                return false
            }

            guard let condition = $0.if?.first else {
                return false
            }

            guard condition.device?.match(with: device) == true else {
                return false
            }

            guard condition.app == app, condition.parentApp == nil, condition.groupApp == nil else {
                return false
            }

            return true
        }
    }
}
