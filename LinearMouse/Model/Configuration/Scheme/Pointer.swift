// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

extension Scheme {
    struct Acceleration: ClampRange {
        typealias Value = Double

        static var range: ClosedRange<Value> = 0 ... 20
    }

    struct Speed: ClampRange {
        typealias Value = Double

        static var range: ClosedRange<Value> = 0 ... 1
    }

    struct Pointer: Codable {
        @Clamp<Acceleration> var acceleration: Double?

        @Clamp<Speed> var speed: Double?

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
