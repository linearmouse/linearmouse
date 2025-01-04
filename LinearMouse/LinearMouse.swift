// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

enum LinearMouse {
    public static var appBundleIdentifier: String {
        Bundle.main.infoDictionary?[kCFBundleIdentifierKey as String] as? String ?? "com.lujjjh.LinearMouse"
    }

    public static var appName: String {
        Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "(unknown)"
    }

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "(unknown)"
    }
}
