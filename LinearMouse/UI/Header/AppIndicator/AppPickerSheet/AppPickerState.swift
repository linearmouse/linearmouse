// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit
import Combine
import Foundation

class AppPickerState: ObservableObject {
    static let shared: AppPickerState = .init()

    private let schemeState: SchemeState = .shared
    private let deviceState: DeviceState = .shared

    @Published var installedApps: [InstalledApp] = []

    private var runningAppSet: Set<String> {
        Set(NSWorkspace.shared.runningApplications.map(\.bundleIdentifier).compactMap { $0 })
    }

    private var configuredAppSet: Set<String> {
        guard let device = deviceState.currentDeviceRef?.value else { return [] }

        return Set(schemeState.schemes.allDeviceSpecficSchemes(of: device).reduce([String]()) { acc, element in
            guard let app = element.element.if?.first?.app else {
                return acc
            }
            return acc + [app]
        })
    }

    var configuredApps: [InstalledApp] {
        configuredAppSet
            .map {
                try? readInstalledApp(bundleIdentifier: $0) ??
                    .init(bundleName: $0,
                          bundleIdentifier: $0,
                          bundleIcon: NSWorkspace.shared.icon(forFile: ""))
            }
            .compactMap { $0 }
    }

    var runningApps: [InstalledApp] {
        let runningAppSet = runningAppSet
        let configuredAppSet = configuredAppSet
        return installedApps
            .filter { runningAppSet.contains($0.bundleIdentifier) && !configuredAppSet.contains($0.bundleIdentifier) }
    }

    var otherApps: [InstalledApp] {
        let runningAppSet = runningAppSet
        let configuredAppSet = configuredAppSet
        return installedApps
            .filter { !runningAppSet.contains($0.bundleIdentifier) && !configuredAppSet.contains($0.bundleIdentifier) }
    }
}

extension AppPickerState {
    func refreshInstalledApps() {
        installedApps = []

        var seenBundleIdentifiers = Set<String>()

        let fileManager = FileManager.default
        for appDirURL in fileManager.urls(for: .applicationDirectory, in: .allDomainsMask) {
            let appURLs = (try? fileManager
                .contentsOfDirectory(at: appDirURL, includingPropertiesForKeys: nil)) ?? []
            for appURL in appURLs {
                guard let installedApp = try? readInstalledApp(at: appURL) else {
                    continue
                }
                guard !seenBundleIdentifiers.contains(installedApp.bundleIdentifier) else {
                    continue
                }
                installedApps.append(installedApp)
                seenBundleIdentifiers.insert(installedApp.bundleIdentifier)
            }
        }
    }
}
