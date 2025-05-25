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
    func isSatisfied(
        withDevice targetDevice: Device? = nil,
        withApp targetApp: String? = nil,
        withParentApp targetParentApp: String?,
        withGroupApp targetGroupApp: String?,
        withDisplay targetDisplay: String? = nil
    ) -> Bool {
        if let device {
            guard let targetDevice else {
                return false
            }

            guard device.match(with: targetDevice) else {
                return false
            }
        }

        if let app {
            guard app == targetApp else {
                return false
            }
        }

        if let parentApp {
            guard parentApp == targetParentApp else {
                return false
            }
        }

        if let groupApp {
            guard groupApp == targetGroupApp else {
                return false
            }
        }

        if let display {
            guard let targetDisplay else {
                return false
            }

            guard display == targetDisplay else {
                return false
            }
        }

        return true
    }
}
