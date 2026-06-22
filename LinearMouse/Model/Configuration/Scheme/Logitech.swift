// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme {
    struct Logitech: Codable, Equatable, ImplicitInitable {
        var highResolutionWheel: Bool?
    }
}

extension Scheme.Logitech {
    func merge(into logitech: inout Self) {
        if let highResolutionWheel {
            logitech.highResolutionWheel = highResolutionWheel
        }
    }

    func merge(into logitech: inout Self?) {
        if logitech == nil {
            logitech = Self()
        }

        merge(into: &logitech!)
    }
}
