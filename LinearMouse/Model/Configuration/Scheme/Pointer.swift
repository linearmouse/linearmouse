// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension Scheme {
    struct Acceleration: ClampRange {
        typealias Value = Decimal

        static var range: ClosedRange<Value> = 0 ... 20
    }

    struct Speed: ClampRange {
        typealias Value = Decimal

        static var range: ClosedRange<Value> = 0 ... 1
    }

    struct Pointer: Codable {
        @Clamp<Acceleration> var acceleration: Decimal?

        @Clamp<Speed> var speed: Decimal?

        var disableAcceleration: Bool?
    }
}

extension Scheme.Pointer {
    func merge(into pointer: inout Self) {
        if let acceleration = acceleration {
            pointer.acceleration = acceleration
        }

        if let speed = speed {
            pointer.speed = speed
        }

        if let disableAcceleration = disableAcceleration {
            pointer.disableAcceleration = disableAcceleration
        }
    }

    func merge(into pointer: inout Self?) {
        if pointer == nil {
            pointer = Self()
        }

        merge(into: &pointer!)
    }
}
