// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import LaunchAtLogin

class AutoStartManager {
    static func enable() {
        LaunchAtLogin.isEnabled = true
    }

    static func disable() {
        LaunchAtLogin.isEnabled = false
    }
}
