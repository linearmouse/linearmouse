// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Defaults
import Foundation
import os.log
import SwiftUI

class ConfigurationState: ObservableObject {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    static let shared = ConfigurationState()

    #if DEBUG
        private static let testConfigurationURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("linearmouse-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("linearmouse.json")
    #endif

    var configurationPaths: [URL] {
        #if DEBUG
            if ProcessEnvironment.isRunningTest {
                return [Self.testConfigurationURL]
            }
        #endif

        var urls: [URL] = []

        if let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first {
            urls.append(
                URL(
                    fileURLWithPath: "linearmouse/linearmouse.json",
                    relativeTo: applicationSupportURL
                )
            )
        }

        // Deprecated: still read so existing configurations keep working, but no
        // longer used for new configurations.
        urls.append(
            URL(
                fileURLWithPath: ".config/linearmouse/linearmouse.json",
                relativeTo: FileManager.default.homeDirectoryForCurrentUser
            )
        )

        return urls
    }

    var configurationPath: URL {
        Self.configurationPath(in: configurationPaths) {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    /// Picks the first existing configuration file in `paths`, which are ordered
    /// by priority. Without one, a new configuration goes to the first path.
    static func configurationPath(in paths: [URL], fileExists: (String) -> Bool) -> URL {
        paths.first { fileExists($0.path) } ?? paths[0]
    }

    private var configurationSaveDebounceTimer: Timer?
    @Published var configuration = Configuration() {
        didSet {
            configurationSaveDebounceTimer?.invalidate()
            guard !loading, ProcessEnvironment.isRunningApp else {
                return
            }

            configurationSaveDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.2,
                repeats: false
            ) { [weak self] _ in
                guard let self else {
                    return
                }

                os_log(
                    "Saving new configuration: %{public}@",
                    log: Self.log,
                    type: .info,
                    String(describing: self.configuration)
                )
                self.save()
            }
        }
    }

    @Published private(set) var loading = false

    private var subscriptions = Set<AnyCancellable>()

    private var configurationFileWatcher: FileWatcher?
    private var reloadDebounceWorkItem: DispatchWorkItem?
}

extension ConfigurationState {
    func reloadFromDisk() {
        let configurationPath = configurationPath
        do {
            let newConfig = try Configuration.load(from: configurationPath)
            guard newConfig != configuration else {
                return
            }

            loading = true
            configuration = newConfig
            loading = false

            os_log("Reloaded configuration from %{public}@", log: Self.log, type: .info, configurationPath.path)

            Notifier.shared.notify(
                title: NSLocalizedString("Configuration Reloaded", comment: ""),
                body: NSLocalizedString("Your configuration changes are now active.", comment: "")
            )
        } catch CocoaError.fileReadNoSuchFile {
            loading = true
            configuration = .init()
            loading = false

            Notifier.shared.notify(
                title: NSLocalizedString("Configuration Reloaded", comment: ""),
                body: NSLocalizedString("Your configuration changes are now active.", comment: "")
            )
        } catch {
            Notifier.shared.notify(
                title: NSLocalizedString("Failed to reload configuration", comment: ""),
                body: error.localizedDescription
            )
        }
    }

    func startHotReload() {
        stopHotReload()

        configurationFileWatcher = FileWatcher(
            fileURLsProvider: { [weak self] in
                self?.configurationPaths ?? []
            },
            queue: .main
        ) { [weak self] in
            self?.scheduleReloadFromExternalChange()
        }
        configurationFileWatcher?.start()
    }

    func stopHotReload() {
        reloadDebounceWorkItem?.cancel()
        reloadDebounceWorkItem = nil

        configurationFileWatcher?.stop()
        configurationFileWatcher = nil
    }

    private func scheduleReloadFromExternalChange() {
        reloadDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadFromDisk()
        }
        reloadDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.shared.configurationPath.absoluteURL])
    }

    func load() {
        loading = true
        defer {
            loading = false
        }

        let configurationPath = configurationPath
        do {
            configuration = try Configuration.load(from: configurationPath)
            os_log("Loaded configuration from %{public}@", log: Self.log, type: .info, configurationPath.path)
            // Publish migration only after its backup and atomic write succeed.
            do {
                try configuration.migrateLegacyGestureButtons(persistingTo: configurationPath)
            } catch {
                os_log(
                    "Gesture migration failed: %{public}@",
                    log: Self.log,
                    type: .error,
                    error.localizedDescription
                )
            }
        } catch CocoaError.fileReadNoSuchFile {
            os_log(
                "No configuration file found, try creating a default one",
                log: Self.log,
                type: .info
            )
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
        guard ProcessEnvironment.isRunningApp else {
            return
        }

        let configurationPath = configurationPath
        do {
            try configuration.dump(to: configurationPath)
            os_log("Saved configuration to %{public}@", log: Self.log, type: .info, configurationPath.path)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(
                format: NSLocalizedString("Failed to save the configuration: %@", comment: ""),
                error.localizedDescription
            )
            alert.runModal()
        }
    }
}
