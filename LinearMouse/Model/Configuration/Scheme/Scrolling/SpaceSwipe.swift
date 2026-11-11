// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme.Scrolling {
    /// Turns horizontal scrolling into the interactive trackpad swipe between
    /// desktop spaces: the space follows the wheel and snaps back unless the
    /// swipe went far or fast enough when the wheel stops.
    struct SpaceSwipe: Equatable, Codable, ImplicitInitable {
        var enabled: Bool?

        /// Horizontal wheel steps that drag one full space.
        var distance: Double?

        /// How long the wheel must be idle before the swipe is released, in milliseconds.
        var releaseDelay: Int?

        init() {}

        init(enabled: Bool? = nil, distance: Double? = nil, releaseDelay: Int? = nil) {
            self.enabled = enabled
            self.distance = distance
            self.releaseDelay = releaseDelay
        }
    }
}

extension Scheme.Scrolling.SpaceSwipe {
    static let distanceRange: ClosedRange<Double> = 1 ... 200
    static let defaultDistance: Double = 12
    static let releaseDelayRange: ClosedRange<Int> = 50 ... 1000
    static let defaultReleaseDelay = 160

    var isEnabled: Bool {
        enabled == true
    }

    var effectiveDistance: Double {
        guard let distance, distance.isFinite else {
            return Self.defaultDistance
        }
        return min(max(distance, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }

    var effectiveReleaseDelay: TimeInterval {
        let value = releaseDelay.map {
            min(max($0, Self.releaseDelayRange.lowerBound), Self.releaseDelayRange.upperBound)
        } ?? Self.defaultReleaseDelay
        return TimeInterval(value) / 1000
    }

    func merge(into spaceSwipe: inout Self) {
        if let enabled {
            spaceSwipe.enabled = enabled
        }
        if let distance {
            spaceSwipe.distance = distance
        }
        if let releaseDelay {
            spaceSwipe.releaseDelay = releaseDelay
        }
    }
}
