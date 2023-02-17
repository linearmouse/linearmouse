// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import AppKit
import Combine
import Foundation

class AppPickerState: ObservableObject {
    static let shared: AppPickerState = .init()

    @Published var installedApps: [InstalledApp] = []

    private var runningAppSet: Set<String?> {
        Set(NSWorkspace.shared.runningApplications.map(\.bundleIdentifier))
    }

    var runningApps: [InstalledApp] {
        let runningAppSet = runningAppSet
        return installedApps.filter { runningAppSet.contains($0.bundleIdentifier) }
    }

    var otherApps: [InstalledApp] {
        let runningAppSet = runningAppSet
        return installedApps.filter { !runningAppSet.contains($0.bundleIdentifier) }
    }
}

extension AppPickerState {
    struct InstalledApp: Identifiable {
        var id: String { bundleIdentifier }

        var bundleName: String
        var bundleIdentifier: String
        var bundleIcon: NSImage
    }

    func refreshInstalledApps(at _: URL? = nil) {
        installedApps = []

        let fileManager = FileManager.default
        for applicationDirectoryURL in fileManager.urls(for: .applicationDirectory, in: .allDomainsMask) {
            let appURLs = (try? fileManager
                .contentsOfDirectory(at: applicationDirectoryURL, includingPropertiesForKeys: nil)) ?? []
            for appURL in appURLs {
                guard let installedApp = try? readInstalledApp(at: appURL) else {
                    continue
                }
                installedApps.append(installedApp)
            }
        }
    }

    private func readInstalledApp(at url: URL) throws -> InstalledApp? {
        guard let bundle = Bundle(url: url) else {
            return nil
        }
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ??
            url.lastPathComponent
        let bundleIcon = NSWorkspace.shared.icon(forFile: url.path)
        bundleIcon.size.width = 16
        bundleIcon.size.height = 16
        return .init(bundleName: bundleName, bundleIdentifier: bundleIdentifier, bundleIcon: bundleIcon)
    }
}
