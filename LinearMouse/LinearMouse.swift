// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

enum LinearMouse {
    static var appBundleIdentifier: String {
        Bundle.main.infoDictionary?[kCFBundleIdentifierKey as String] as? String ?? "com.lujjjh.LinearMouse"
    }

    static var appName: String {
        Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "(unknown)"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "(unknown)"
    }
}
