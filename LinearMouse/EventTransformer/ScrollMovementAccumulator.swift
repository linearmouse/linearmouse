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
        var roundToNearestStep: Bool
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

    func consume(_ input: ScrollInput, mapping: Int, roundToNearestStep: Bool = false, at now: UInt64) -> Int {
        guard input.delta.isFinite, input.delta != 0 else {
            return 0
        }
        let direction = input.delta > 0 ? 1.0 : -1.0
        let delta = input.delta
        var state = states[input.axis]
        if let previous = state,
           previous.units != input.units || previous.hasPhase != input.hasPhase ||
           previous.roundToNearestStep != roundToNearestStep ||
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
            hasPhase: input.hasPhase,
            roundToNearestStep: roundToNearestStep
        )
        current.lastTime = now
        current.remainder += delta
        let threshold = input.units.threshold
        let offset = roundToNearestStep ? threshold / 2 : 0
        // Measure in the input direction: a negative remainder after rounding
        // is distance owed, not fresh movement in the opposite direction.
        let progress = direction * current.remainder
        let steps = max(0, floor((progress + offset + 1e-9) / threshold))
        // Reject unrepresentable input rather than allocating work proportional to it.
        guard steps < Double(Int.max) else {
            states.removeValue(forKey: input.axis)
            return 0
        }
        let count = Int(steps)
        let remainder = progress - steps * threshold
        // Like the high-resolution line-scroll counter, retain the negative
        // remainder after the first half step so subsequent steps are a full step apart.
        current.remainder = direction * (roundToNearestStep ? remainder : max(0, remainder))
        states[input.axis] = current
        return count
    }
}
