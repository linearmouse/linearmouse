// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import AppKit
import Foundation
import LRUCache

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(range.lowerBound, self), range.upperBound)
    }
}

extension BinaryInteger {
    func normalized(fromLowerBound: Self = 0, fromUpperBound: Self = 1, toLowerBound: Self = 0,
                    toUpperBound: Self = 1) -> Self {
        let k = (toUpperBound - toLowerBound) / (fromUpperBound - fromLowerBound)
        return (self - fromLowerBound) * k + toLowerBound
    }

    func normalized(from: ClosedRange<Self> = 0 ... 1, to: ClosedRange<Self> = 0 ... 1) -> Self {
        normalized(fromLowerBound: from.lowerBound, fromUpperBound: from.upperBound,
                   toLowerBound: to.lowerBound, toUpperBound: to.upperBound)
    }
}

extension BinaryFloatingPoint {
    func normalized(fromLowerBound: Self = 0, fromUpperBound: Self = 1, toLowerBound: Self = 0,
                    toUpperBound: Self = 1) -> Self {
        let k = (toUpperBound - toLowerBound) / (fromUpperBound - fromLowerBound)
        return (self - fromLowerBound) * k + toLowerBound
    }

    func normalized(from: ClosedRange<Self> = 0 ... 1, to: ClosedRange<Self> = 0 ... 1) -> Self {
        normalized(fromLowerBound: from.lowerBound, fromUpperBound: from.upperBound,
                   toLowerBound: to.lowerBound, toUpperBound: to.upperBound)
    }
}

extension Decimal {
    var asTruncatedDouble: Double {
        Double(truncating: self as NSNumber)
    }

    func rounded(_ scale: Int) -> Self {
        var roundedValue = Decimal()
        var mutableSelf = self
        NSDecimalRound(&roundedValue, &mutableSelf, scale, .plain)
        return roundedValue
    }
}

extension pid_t {
    private static var bundleIdentifierCache = LRUCache<Self, String>(countLimit: 16)

    var bundleIdentifier: String? {
        guard let bundleIdentifier = Self.bundleIdentifierCache.value(forKey: self)
            ?? NSRunningApplication(processIdentifier: self)?.bundleIdentifier
        else {
            return nil
        }

        Self.bundleIdentifierCache.setValue(bundleIdentifier, forKey: self)

        return bundleIdentifier
    }

    var parent: pid_t? {
        let pid = getProcessInfo(self).ppid

        guard pid > 0 else {
            return nil
        }

        return pid
    }

    var group: pid_t? {
        let pid = getProcessInfo(self).pgid

        guard pid > 0 else {
            return nil
        }

        return pid
    }
}
