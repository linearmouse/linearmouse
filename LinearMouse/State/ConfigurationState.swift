// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import AppKit
import Combine
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

    @Published var configuration = Configuration() {
        didSet {
            guard shouldAutoSaveConfiguration else {
                return
            }

            os_log("Saving new configuration: %{public}@", log: Self.log, type: .debug,
                   String(describing: configuration))
            save()
        }
    }

    private var shouldAutoSaveConfiguration = true

    @Published var activeScheme: Scheme? {
        didSet {
            guard let activeScheme = activeScheme else {
                os_log("Active scheme is updated: nil", log: Self.log, type: .debug,
                       String(describing: activeScheme))
                return
            }
            os_log("Active scheme is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: activeScheme))
        }
    }

    @Published var currentDeviceSchemeIndex: Int? {
        didSet {
            os_log("Current device scheme index is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: currentDeviceSchemeIndex))
        }
    }

    private var subscriptions = Set<AnyCancellable>()

    init() {
        load()

        DeviceManager.shared.$lastActiveDevice.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateActiveScheme()
            }
        }
        .store(in: &subscriptions)

        DeviceState.shared.$currentDevice.sink { [weak self] _ in
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
            updateActiveScheme()
            updateCurrentDeviceScheme()
        } catch CocoaError.fileReadNoSuchFile {
            os_log("No configuration file found, try creating a default one", log: Self.log, type: .debug)
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

    func updateActiveScheme() {
        activeScheme = configuration.activeScheme
    }

    func updateCurrentDeviceScheme() {
        currentDeviceSchemeIndex = DeviceState.shared.currentDevice.flatMap { device in
            configuration.schemes.firstIndex {
                guard $0.isDeviceSpecific else { return false }

                return $0.if?.contains { $0.isSatisfied(withDevice: device) } == true
            }
        }
    }

    func getSchemeIndex(forDevice device: Device?) -> Int? {
        guard let device = device else {
            return nil
        }

        return configuration.schemes.firstIndex {
            guard $0.isDeviceSpecific else { return false }

            return $0.if?.contains { $0.isSatisfied(withDevice: device) } == true
        }
    }
}
