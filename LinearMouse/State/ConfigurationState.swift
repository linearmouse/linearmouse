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

    var configurationPaths: [URL] {
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

        urls.append(
            URL(
                fileURLWithPath: ".config/linearmouse/linearmouse.json",
                relativeTo: FileManager.default.homeDirectoryForCurrentUser
            )
        )

        return urls
    }

    var configurationPath: URL {
        configurationPaths.first { FileManager.default.fileExists(atPath: $0.path) } ?? configurationPaths
            .last!
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
        do {
            let newConfig = try Configuration.load(from: configurationPath)
            guard newConfig != configuration else {
                return
            }

            loading = true
            configuration = newConfig
            loading = false

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
        NSWorkspace.shared.activateFileViewerSelecting([ConfigurationState.shared.configurationPath.absoluteURL])
    }

    func load() {
        loading = true
        defer {
            loading = false
        }

        do {
            configuration = try Configuration.load(from: configurationPath)
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
}
