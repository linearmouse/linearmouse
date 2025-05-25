// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

extension Scheme {
    struct Acceleration: Equatable, ClampRange {
        typealias Value = Decimal

        static var range: ClosedRange<Value> = 0 ... 20
    }

    struct Speed: Equatable, ClampRange {
        typealias Value = Decimal

        static var range: ClosedRange<Value> = 0 ... 1
    }

    struct Pointer: Codable, Equatable, ImplicitInitable {
        @Clamp<Acceleration> var acceleration: Decimal?

        @Clamp<Speed> var speed: Decimal?

        var disableAcceleration: Bool?
        var redirectsToScroll: Bool?
    }
}

extension Scheme.Pointer {
    func merge(into pointer: inout Self) {
        if let acceleration {
            pointer.acceleration = acceleration
        }

        if let speed {
            pointer.speed = speed
        }

        if let disableAcceleration {
            pointer.disableAcceleration = disableAcceleration
        }

        if let redirectsToScroll {
            pointer.redirectsToScroll = redirectsToScroll
        }
    }

    func merge(into pointer: inout Self?) {
        if pointer == nil {
            pointer = Self()
        }

        merge(into: &pointer!)
    }
}
