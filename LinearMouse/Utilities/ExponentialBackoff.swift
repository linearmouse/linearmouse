// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

struct ExponentialBackoff {
    let initialDelay: TimeInterval
    let maximumDelay: TimeInterval
    let multiplier: Double

    private var delay: TimeInterval

    init(
        initialDelay: TimeInterval,
        maximumDelay: TimeInterval,
        multiplier: Double = 2
    ) {
        precondition(initialDelay >= 0)
        precondition(maximumDelay >= initialDelay)
        precondition(multiplier >= 1)

        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.multiplier = multiplier
        delay = initialDelay
    }

    mutating func nextDelay() -> TimeInterval {
        defer { delay = min(delay * multiplier, maximumDelay) }
        return delay
    }

    mutating func reset() {
        delay = initialDelay
    }
}
