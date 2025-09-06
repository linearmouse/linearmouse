// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine
import Darwin
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
        configurationPaths.first { FileManager.default.fileExists(atPath: $0.absoluteString) } ?? configurationPaths
            .last!
    }

    private var configurationSaveDebounceTimer: Timer?
    @Published var configuration = Configuration() {
        didSet {
            configurationSaveDebounceTimer?.invalidate()
            guard !loading else {
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

    // Hot reload support (watch parent directory and resolved target file)
    private var configDirFD: CInt?
    private var configDirSource: DispatchSourceFileSystemObject?
    private var configFileFD: CInt?
    private var configFileSource: DispatchSourceFileSystemObject?
    private var watchedFilePath: String?
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

        // Directory watcher
        let directoryURL = configurationPath.deletingLastPathComponent()
        let dirFD = open(directoryURL.path, O_EVTONLY)
        guard dirFD >= 0 else {
            return
        }
        configDirFD = dirFD

        let dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .attrib, .rename, .link, .delete, .extend, .revoke],
            queue: .main
        )

        dirSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            // Any directory entry change may indicate symlink retarget, file replace, create/delete, etc.
            self.updateFileWatcherIfNeeded()
            self.scheduleReloadFromExternalChange()
        }

        dirSource.setCancelHandler { [weak self] in
            if let fd = self?.configDirFD {
                close(fd)
            }
            self?.configDirFD = nil
        }

        configDirSource = dirSource
        dirSource.resume()

        // File watcher for resolved target (or the file itself if not a symlink)
        updateFileWatcherIfNeeded()
    }

    func stopHotReload() {
        reloadDebounceWorkItem?.cancel()
        reloadDebounceWorkItem = nil

        configDirSource?.cancel()
        configDirSource = nil
        if let fd = configDirFD {
            close(fd)
        }
        configDirFD = nil

        configFileSource?.cancel()
        configFileSource = nil
        if let fd = configFileFD {
            close(fd)
        }
        configFileFD = nil
        watchedFilePath = nil
    }

    private func scheduleReloadFromExternalChange() {
        reloadDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadFromDisk()
        }
        reloadDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func updateFileWatcherIfNeeded() {
        // Watch resolved target file (or the file itself if not a symlink)
        let linkPath = configurationPath.path
        let resolvedPath = (linkPath as NSString).resolvingSymlinksInPath

        // If path unchanged, nothing to do
        if watchedFilePath == resolvedPath, configFileSource != nil {
            // Still ensure file exists; if gone, drop watcher so directory watcher can recreate later
            if !FileManager.default.fileExists(atPath: resolvedPath) {
                configFileSource?.cancel()
                configFileSource = nil
                if let fd = configFileFD {
                    close(fd)
                }
                configFileFD = nil
                watchedFilePath = nil
            }
            return
        }

        // Path changed or no watcher; rebuild
        configFileSource?.cancel()
        configFileSource = nil
        if let fd = configFileFD {
            close(fd)
        }
        configFileFD = nil
        watchedFilePath = nil

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return
        }

        let fd = open(resolvedPath, O_EVTONLY)
        guard fd >= 0 else {
            return
        }
        configFileFD = fd

        let fileSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .attrib, .extend, .delete, .rename, .revoke, .link],
            queue: .main
        )

        fileSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let events = fileSource.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                // File removed/replaced; drop watcher and rely on directory watcher to re-add
                self.configFileSource?.cancel()
                self.configFileSource = nil
                if let fd = self.configFileFD {
                    close(fd)
                }
                self.configFileFD = nil
                self.watchedFilePath = nil
                self.scheduleReloadFromExternalChange()
            } else {
                self.scheduleReloadFromExternalChange()
            }
        }

        fileSource.setCancelHandler { [weak self] in
            if let fd = self?.configFileFD {
                close(fd)
            }
            self?.configFileFD = nil
        }

        configFileSource = fileSource
        watchedFilePath = resolvedPath
        fileSource.resume()
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
