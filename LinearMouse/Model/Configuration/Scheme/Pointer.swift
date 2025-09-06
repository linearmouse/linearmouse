// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

extension Scheme {
    struct Acceleration: Equatable, ClampRange {
        typealias Value = Unsettable<Decimal>
        typealias RangeValue = Decimal

        static var range: ClosedRange<RangeValue> = 0 ... 20

        static func clamp(_ value: Value?) -> Value? {
            guard let value else {
                return nil
            }
            switch value {
            case let .value(v):
                return .value(v.clamped(to: range))
            case .unset:
                return .unset
            }
        }
    }

    struct Speed: Equatable, ClampRange {
        typealias Value = Unsettable<Decimal>
        typealias RangeValue = Decimal

        static var range: ClosedRange<RangeValue> = 0 ... 1

        static func clamp(_ value: Value?) -> Value? {
            guard let value else {
                return nil
            }
            switch value {
            case let .value(v):
                return .value(v.clamped(to: range))
            case .unset:
                return .unset
            }
        }
    }

    struct Pointer: Codable, Equatable, ImplicitInitable {
        @Clamp<Acceleration> var acceleration: Unsettable<Decimal>?

        @Clamp<Speed> var speed: Unsettable<Decimal>?

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
