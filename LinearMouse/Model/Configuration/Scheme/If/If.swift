// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

extension Scheme {
    struct If: Codable {
        var device: DeviceMatcher?

        var app: String?
        var parentApp: String?
        var groupApp: String?
    }
}

extension Scheme.If {
    func isSatisfied(withDevice targetDevice: Device? = nil,
                     withPid pid: pid_t? = nil) -> Bool {
        if let device = device {
            guard let targetDevice = targetDevice else {
                return false
            }

            guard device.match(with: targetDevice) else {
                return false
            }
        }

        if let app = app {
            guard pid?.bundleIdentifier == app else {
                return false
            }
        }

        if let parentApp = parentApp {
            guard pid?.parent?.bundleIdentifier == parentApp else {
                return false
            }
        }

        if let groupApp = groupApp {
            guard pid?.group?.bundleIdentifier == groupApp else {
                return false
            }
        }

        return true
    }
}
