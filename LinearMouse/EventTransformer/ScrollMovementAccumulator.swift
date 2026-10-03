// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Route-local distance accounting. It never grants permission to execute commands.
final class ScrollMovementAccumulator {
    private typealias Axis = ScrollInput.Axis
    private typealias Units = ScrollInput.Units
    private struct State {
        var units: Units
        var mapping: Int
        var direction: Double
        var remainder = 0.0
        var lastTime: UInt64
        var hasPhase: Bool
    }

    private var states: [Axis: State] = [:]

    /// Snapshot the remainder for a gesture tail independently of route teardown.
    func snapshot() -> ScrollMovementAccumulator {
        let copy = ScrollMovementAccumulator()
        copy.states = states
        return copy
    }

    func discard(on axis: ScrollInput.Axis? = nil) {
        if let axis {
            states.removeValue(forKey: axis)
        } else {
            states.removeAll()
        }
    }

    func consume(_ input: ScrollInput, mapping: Int, at now: UInt64) -> Int {
        guard input.delta.isFinite, input.delta != 0 else {
            return 0
        }
        let direction = input.delta > 0 ? 1.0 : -1.0
        let delta = input.delta
        var state = states[input.axis]
        if let previous = state,
           previous.units != input.units || previous.hasPhase != input.hasPhase ||
           previous.mapping != mapping || previous.direction != direction || now < previous.lastTime ||
           (!input.hasPhase && now - previous.lastTime >
               (input.units == .detents ? 1_000_000_000 : 500_000_000)) {
            state = nil
        }
        var current = state ?? State(
            units: input.units,
            mapping: mapping,
            direction: direction,
            lastTime: now,
            hasPhase: input.hasPhase
        )
        current.lastTime = now
        current.remainder += delta
        let steps = floor((abs(current.remainder) + 1e-9) / input.units.threshold)
        // Reject unrepresentable input rather than allocating work proportional to it.
        guard steps < Double(Int.max) else {
            states.removeValue(forKey: input.axis)
            return 0
        }
        let count = Int(steps)
        current.remainder = direction * max(0, abs(current.remainder) - steps * input.units.threshold)
        states[input.axis] = current
        return count
    }
}
