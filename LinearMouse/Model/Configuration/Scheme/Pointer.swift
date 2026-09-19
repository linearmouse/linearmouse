// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme {
    struct Acceleration: Equatable, ClampRange {
        typealias Value = Unsettable<Decimal>
        typealias RangeValue = Decimal

        static var range: ClosedRange<RangeValue> = 0 ... 40

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

        var hardwareDPI: Int?

        var disableAcceleration: Bool?
        var redirectsToScroll: Bool?
        /// When set, pointer movement is redirected to scrolling only while
        /// this trigger is held. Requires `redirectsToScroll`.
        var redirectsToScrollTrigger: Trigger?
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

        if let hardwareDPI {
            pointer.hardwareDPI = hardwareDPI
        }

        if let disableAcceleration {
            pointer.disableAcceleration = disableAcceleration
        }

        if let redirectsToScroll {
            pointer.redirectsToScroll = redirectsToScroll
        }

        if let redirectsToScrollTrigger {
            pointer.redirectsToScrollTrigger = redirectsToScrollTrigger
        }
    }

    func merge(into pointer: inout Self?) {
        if pointer == nil {
            pointer = Self()
        }

        merge(into: &pointer!)
    }
}

extension Scheme.Trigger {
    /// Whether this trigger can be held to redirect pointer movement to scrolling.
    ///
    /// Only a single mouse button, optionally with modifier keys, is supported.
    /// The primary button without modifier keys is rejected because it would
    /// take over every click.
    var isValidRedirectsToScrollTrigger: Bool {
        guard case let .button(.mouse(buttonNumber)) = input,
              (simultaneous ?? []).isEmpty,
              (whileHeld ?? []).isEmpty else {
            return false
        }

        return buttonNumber != 0 || !modifierFlags.isEmpty
    }
}
