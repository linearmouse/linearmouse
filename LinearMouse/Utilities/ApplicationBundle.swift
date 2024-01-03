// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit
import Foundation

struct InstalledApp: Identifiable {
    var id: String { bundleIdentifier }

    var bundleName: String
    var bundleIdentifier: String
    var bundleIcon: NSImage
}

func readInstalledApp(at url: URL) throws -> InstalledApp? {
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

func readInstalledApp(bundleIdentifier: String) throws -> InstalledApp? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        return nil
    }
    return try readInstalledApp(at: url)
}
