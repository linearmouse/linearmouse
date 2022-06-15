// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

class LinearMouse {
    public static var appName: String {
        Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "(unknown)"
    }

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "(unknown)"
    }
}
