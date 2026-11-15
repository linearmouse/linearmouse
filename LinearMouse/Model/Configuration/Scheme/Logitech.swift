// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme {
    struct Logitech: Codable, Equatable, ImplicitInitable {
        var highResolutionWheel: Bool?

        var invertWheel: Bool?
    }
}

extension Scheme.Logitech {
    func merge(into logitech: inout Self) {
        if let highResolutionWheel {
            logitech.highResolutionWheel = highResolutionWheel
        }

        if let invertWheel {
            logitech.invertWheel = invertWheel
        }
    }

    func merge(into logitech: inout Self?) {
        if logitech == nil {
            logitech = Self()
        }

        merge(into: &logitech!)
    }
}

extension Scheme {
    /// The in-mouse wheel reversal to manage. `invertWheel` refines vertical
    /// reverse scrolling: it moves that reversal into the mouse, so it applies
    /// only while vertical reverse scrolling is on too. Otherwise it is
    /// unmanaged and the mouse returns to its own direction.
    var managedLogitechWheelInvert: Bool? {
        logitech.invertWheel == true && scrolling.reverse.vertical == true ? true : nil
    }
}
