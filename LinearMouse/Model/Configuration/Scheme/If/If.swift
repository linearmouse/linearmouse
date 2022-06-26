// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

extension Scheme {
    struct If: Codable {
        var device: DeviceMatcher?
    }
}

extension Scheme.If {
    func isSatisfied(withDevice targetDevice: Device?) -> Bool {
        if let device = device {
            guard let targetDevice = targetDevice else {
                return false
            }
            guard device.match(with: targetDevice) else { return false }
        }

        return true
    }
}
