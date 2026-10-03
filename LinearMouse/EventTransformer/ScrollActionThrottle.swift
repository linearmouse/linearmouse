// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Device-local leading-edge throttle. Only accepted commands advance the deadline.
/// Directions share a deadline on each axis; unrelated input cannot reset it.
final class ScrollActionThrottle {
    private static let intervalNanoseconds: UInt64 = 300_000_000
    private var lastActionTimes: [ScrollInput.Axis: UInt64] = [:]

    func allowsAction(on axis: ScrollInput.Axis, at now: UInt64) -> Bool {
        if let last = lastActionTimes[axis], now >= last, now - last < Self.intervalNanoseconds {
            return false
        }
        lastActionTimes[axis] = now
        return true
    }

    /// For configuration resets or recording, not ordinary input transitions.
    func reset() {
        lastActionTimes.removeAll()
    }
}
