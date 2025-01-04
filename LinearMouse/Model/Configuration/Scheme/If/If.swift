// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Foundation

extension Scheme {
    struct If: Codable, Equatable {
        var device: DeviceMatcher?

        var app: String?
        var parentApp: String?
        var groupApp: String?

        var display: String?
    }
}

extension Scheme.If {
    func isSatisfied(withDevice targetDevice: Device? = nil,
                     withApp targetApp: String? = nil,
                     withParentApp targetParentApp: String?,
                     withGroupApp targetGroupApp: String?,
                     withDisplay targetDisplay: String? = nil) -> Bool {
        if let device = device {
            guard let targetDevice = targetDevice else {
                return false
            }

            guard device.match(with: targetDevice) else {
                return false
            }
        }

        if let app = app {
            guard app == targetApp else {
                return false
            }
        }

        if let parentApp = parentApp {
            guard parentApp == targetParentApp else {
                return false
            }
        }

        if let groupApp = groupApp {
            guard groupApp == targetGroupApp else {
                return false
            }
        }

        if let display = display {
            guard let targetDisplay = targetDisplay else {
                return false
            }

            guard display == targetDisplay else {
                return false
            }
        }

        return true
    }
}
