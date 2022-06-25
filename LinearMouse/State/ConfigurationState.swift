// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import AppKit
import Combine
import Foundation
import os.log

class ConfigurationState: ObservableObject {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    static let shared = ConfigurationState()

    let configurationPath = URL(
        fileURLWithPath: ".config/linearmouse/linearmouse.json",
        relativeTo: FileManager.default.homeDirectoryForCurrentUser
    )

    @Published var configuration = Configuration()

    @Published var activeScheme: Scheme? {
        didSet {
            os_log("Active scheme is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: activeScheme))
        }
    }

    @Published var activeDeviceSpecificSchemeIndex: Int? {
        didSet {
            os_log("Active device specific scheme index is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: activeDeviceSpecificSchemeIndex))
        }
    }

    @Published var activeDeviceSpecificScheme: Scheme? {
        didSet {
            os_log("Active device-specific scheme is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: activeDeviceSpecificScheme))
        }
    }

    private var subscriptions = Set<AnyCancellable>()

    init() {
        load()
        save()

        DeviceManager.shared.$lastActiveDevice.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateActiveScheme()
                self?.updateActiveDeviceSpecificScheme()
            }
        }
        .store(in: &subscriptions)
    }
}

extension ConfigurationState {
    func load() {
        do {
            configuration = try Configuration.load(from: configurationPath)
            updateActiveScheme()
            updateActiveDeviceSpecificScheme()
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

    func updateActiveDeviceSpecificScheme() {
        activeDeviceSpecificSchemeIndex = configuration.activeDeviceSpecificSchemeIndex
    }
}
