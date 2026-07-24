// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation
import LRUCache
import SwiftUI

private let wholePercentNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return formatter
}()

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(range.lowerBound, self), range.upperBound)
    }
}

extension BinaryInteger {
    func normalized(
        fromLowerBound: Self = 0,
        fromUpperBound: Self = 1,
        toLowerBound: Self = 0,
        toUpperBound: Self = 1
    ) -> Self {
        let k = (toUpperBound - toLowerBound) / (fromUpperBound - fromLowerBound)
        return (self - fromLowerBound) * k + toLowerBound
    }

    func normalized(from: ClosedRange<Self> = 0 ... 1, to: ClosedRange<Self> = 0 ... 1) -> Self {
        normalized(
            fromLowerBound: from.lowerBound,
            fromUpperBound: from.upperBound,
            toLowerBound: to.lowerBound,
            toUpperBound: to.upperBound
        )
    }
}

extension BinaryFloatingPoint {
    func normalized(
        fromLowerBound: Self = 0,
        fromUpperBound: Self = 1,
        toLowerBound: Self = 0,
        toUpperBound: Self = 1
    ) -> Self {
        let k = (toUpperBound - toLowerBound) / (fromUpperBound - fromLowerBound)
        return (self - fromLowerBound) * k + toLowerBound
    }

    func normalized(from: ClosedRange<Self> = 0 ... 1, to: ClosedRange<Self> = 0 ... 1) -> Self {
        normalized(
            fromLowerBound: from.lowerBound,
            fromUpperBound: from.upperBound,
            toLowerBound: to.lowerBound,
            toUpperBound: to.upperBound
        )
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

func formattedPercent<Value: BinaryInteger>(_ value: Value) -> String {
    wholePercentNumberFormatter.string(from: NSNumber(value: Double(Int(value)) / 100.0))
        ?? "\(value)%"
}

struct ProcessIdentity: Hashable {
    let pid: pid_t
    let startTimeSeconds: UInt64
    let startTimeMicroseconds: UInt64

    init(pid: pid_t, startTimeSeconds: UInt64, startTimeMicroseconds: UInt64) {
        self.pid = pid
        self.startTimeSeconds = startTimeSeconds
        self.startTimeMicroseconds = startTimeMicroseconds
    }

    init?(pid: pid_t) {
        let info = getProcessInfo(pid)
        guard info.startTimeSeconds > 0 else {
            return nil
        }

        self.init(
            pid: pid,
            startTimeSeconds: info.startTimeSeconds,
            startTimeMicroseconds: info.startTimeMicroseconds
        )
    }

    var bundleIdentifier: String? {
        pid.bundleIdentifier(for: self)
    }

    var processPath: String? {
        pid.processPath(for: self)
    }

    var processName: String? {
        pid.processName(for: self)
    }

    var parent: Self? {
        pid.parent.flatMap { Self(pid: $0) }
    }

    var group: Self? {
        pid.group.flatMap { Self(pid: $0) }
    }
}

final class ProcessMetadataCache<Value> {
    private let cache: LRUCache<ProcessIdentity, Value>

    init(countLimit: Int) {
        cache = LRUCache(countLimit: countLimit)
    }

    func value(for key: ProcessIdentity?, load: () -> Value?) -> Value? {
        if let key, let cached = cache.value(forKey: key) {
            return cached
        }

        guard let value = load() else {
            return nil
        }

        if let key {
            cache.setValue(value, forKey: key)
        }

        return value
    }
}

extension pid_t {
    private static let bundleIdentifierCache = ProcessMetadataCache<String>(countLimit: 16)
    private static let processPathCache = ProcessMetadataCache<String>(countLimit: 16)
    private static let processNameCache = ProcessMetadataCache<String>(countLimit: 16)

    var processIdentity: ProcessIdentity? {
        ProcessIdentity(pid: self)
    }

    var bundleIdentifier: String? {
        bundleIdentifier(for: processIdentity)
    }

    fileprivate func bundleIdentifier(for processIdentity: ProcessIdentity?) -> String? {
        Self.bundleIdentifierCache.value(for: processIdentity) {
            NSRunningApplication(processIdentifier: self)?.bundleIdentifier
        }
    }

    var processPath: String? {
        processPath(for: processIdentity)
    }

    fileprivate func processPath(for processIdentity: ProcessIdentity?) -> String? {
        Self.processPathCache.value(for: processIdentity) {
            NSRunningApplication(processIdentifier: self)?.executableURL?.path
        }
    }

    var processName: String? {
        processName(for: processIdentity)
    }

    fileprivate func processName(for processIdentity: ProcessIdentity?) -> String? {
        Self.processNameCache.value(for: processIdentity) {
            NSRunningApplication(processIdentifier: self)?.executableURL?.lastPathComponent
        }
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

extension CGMouseButton {
    static let back = CGMouseButton(rawValue: 3)!
    static let forward = CGMouseButton(rawValue: 4)!

    func fixedCGEventType(of eventType: CGEventType) -> CGEventType {
        func fixed(of type: CGEventType, _ l: CGEventType, _ r: CGEventType, _ o: CGEventType) -> CGEventType {
            guard type == l || type == r || type == o else {
                return type
            }
            return self == .left ? l : self == .right ? r : o
        }

        var eventType = eventType
        eventType = fixed(of: eventType, .leftMouseDown, .rightMouseDown, .otherMouseDown)
        eventType = fixed(of: eventType, .leftMouseUp, .rightMouseUp, .otherMouseUp)
        eventType = fixed(of: eventType, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged)
        return eventType
    }
}

extension CGMouseButton: Codable {}

extension Binding {
    func `default`<UnwrappedValue>(_ value: UnwrappedValue) -> Binding<UnwrappedValue> where Value == UnwrappedValue? {
        Binding<UnwrappedValue>(get: { wrappedValue ?? value }, set: { wrappedValue = $0 })
    }
}
