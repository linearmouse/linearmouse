// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

extension Scheme {
    struct If: Codable {
        var device: DeviceMatcher?
    }
}

extension Scheme.If {
    var isTruthy: Bool {
        if let device = device {
            guard let activeDevice = DeviceManager.shared.lastActiveDevice else {
                return false
            }
            guard device.match(with: activeDevice) else { return false }
        }

        return true
    }
}
