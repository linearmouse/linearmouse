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
        fileURLWithPath: ".config/linearmouse/config.json",
        relativeTo: FileManager.default.homeDirectoryForCurrentUser
    )

    private var shouldPerformSave = false

    /// After being set, it will be saved to the disk automatically
    /// in the next main loop.
    @Published var configuration = ConfigurationRoot() {
        didSet {
            shouldPerformSave = true

            DispatchQueue.main.async { [self] in
                guard shouldPerformSave else { return }

                save()
                shouldPerformSave = false
            }
        }
    }

    @Published var activeScheme: ConfigurationScheme? {
        didSet {
            os_log("Active scheme is switched to %{public}@", log: Self.log, type: .debug,
                   String(describing: activeScheme))
        }
    }

    private var subscriptions = Set<AnyCancellable>()

    init() {
        load()

        $configuration.sink { [weak self] configuration in
            self?.updateActiveScheme(of: configuration)
        }
        .store(in: &subscriptions)

        DeviceManager.shared.$lastActiveDevice.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateActiveScheme()
            }
        }
        .store(in: &subscriptions)
    }
}

extension ConfigurationState {
    func load() {
        do {
            configuration = try ConfigurationRoot.load(from: configurationPath)
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
        updateActiveScheme(of: configuration)
    }

    func updateActiveScheme(of configuration: ConfigurationRoot) {
        activeScheme = configuration.activeScheme
    }
}
