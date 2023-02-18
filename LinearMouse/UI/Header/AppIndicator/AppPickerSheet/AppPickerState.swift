// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

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
        guard let device = deviceState.currentDevice else { return [] }
        return Set(schemeState.allDeviceSpecficSchemes(of: device).reduce([String]()) { acc, element in
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
}
