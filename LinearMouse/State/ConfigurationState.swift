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

    @Published var currentDeviceSchemeIndex: Int? {
        didSet {
            os_log("Current device scheme index is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: currentDeviceSchemeIndex))
        }
    }

    private var subscriptions = Set<AnyCancellable>()

    init() {
        DeviceState.shared.$currentDevice
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateCurrentDeviceScheme()
                }
            }
            .store(in: &subscriptions)
    }
}

extension ConfigurationState {
    func load() {
        shouldAutoSaveConfiguration = false
        defer {
            shouldAutoSaveConfiguration = true
        }

        do {
            configuration = try Configuration.load(from: configurationPath)
            updateCurrentDeviceScheme()
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

    func updateCurrentDeviceScheme() {
        currentDeviceSchemeIndex = DeviceState.shared.currentDevice.flatMap { device in
            configuration.schemes.firstIndex {
                guard $0.isDeviceSpecific else { return false }

                return $0.if?.contains { $0.isSatisfied(withDevice: device) } == true
            }
        }
    }

    func getSchemeIndex(forDevice device: Device) -> Int? {
        configuration.schemes.firstIndex {
            guard $0.isDeviceSpecific else { return false }

            return $0.if?.contains { $0.isSatisfied(withDevice: device) } == true
        }
    }
}
