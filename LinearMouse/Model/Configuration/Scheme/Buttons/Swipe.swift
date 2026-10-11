// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme.Buttons {
    struct Swipe: Codable, Equatable, ImplicitInitable {
        static let thresholdRange: ClosedRange<Double> = 10 ... 200
        static let defaultThreshold: Double = 50

        var threshold: Double?
        var lockPointer: Bool?

        var effectiveThreshold: Double {
            guard let threshold, threshold.isFinite else {
                return Self.defaultThreshold
            }
            return min(max(threshold, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)
        }

        func merge(into swipe: inout Self) {
            if let threshold {
                swipe.threshold = threshold
            }
            if let lockPointer {
                swipe.lockPointer = lockPointer
            }
        }
    }
}
