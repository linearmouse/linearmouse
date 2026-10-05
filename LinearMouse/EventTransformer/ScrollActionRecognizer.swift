// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Route-local coordinator. Only the throttle and gesture ownership are shared
/// across routes; distance accumulated for one mapping cannot leak into another.
final class ScrollActionRecognizer {
    typealias Axis = ScrollInput.Axis
    typealias Input = ScrollInput

    private let throttle: ScrollActionThrottle
    private let gesture: ScrollGestureOwnership
    private let movement = ScrollMovementAccumulator()
    private var modifierFlags: UInt64?

    init(throttle: ScrollActionThrottle = .init(), gesture: ScrollGestureOwnership = .init()) {
        self.throttle = throttle
        self.gesture = gesture
    }

    /// Pin the output mapping and its fractional remainder to the gesture, not
    /// the route that happens to be active when momentum arrives.
    func retainScrollMomentum(
        input: Input,
        mapping: Int,
        action: Scheme.Buttons.Mapping.Action,
        highResolutionMultiplier: Int?,
        clock: @escaping () -> UInt64,
        perform: @escaping (Scheme.Buttons.Mapping.Action) -> Void
    ) {
        let tailMovement = movement.snapshot()
        gesture.retainScroll { view in
            guard var tail = ScrollInput.read(
                from: view, highResolutionMultiplier: highResolutionMultiplier, axis: input.axis
            ) else {
                return
            }
            // Reversal and modifier changes must not select a different mapping
            // during an already-owned tail. Momentum has no direct-input phase.
            tail.delta = abs(tail.delta) * (input.delta > 0 ? 1 : -1)
            tail.hasPhase = input.hasPhase
            let count = tailMovement.consume(tail, mapping: mapping, at: clock())
            if count > 0 {
                perform(action.coalescingScrollSteps(count))
            }
        }
    }

    func updateModifiers(_ flags: UInt64) {
        if let modifierFlags, modifierFlags != flags {
            movement.discard()
        }
        modifierFlags = flags
    }

    var ownsGesture: Bool {
        gesture.isOwned
    }

    func discardMovement(on axis: Axis? = nil) {
        movement.discard(on: axis)
    }

    /// Explicit global reset, used when recording or resetting configuration.
    func reset() {
        movement.discard()
        throttle.reset()
        gesture.release()
    }

    func beginGesture() {
        movement.discard()
        gesture.release()
    }

    func endGesture() {
        movement.discard()
        // Keep ownership through the momentum tail, independent of the cooldown.
    }

    func consume(_ input: Input, mapping: Int, repeats: Bool, at now: UInt64) -> Int {
        guard input.delta.isFinite, input.delta != 0 else {
            return 0
        }
        // Ownership follows consumption, not resolution or a guessed detent type.
        gesture.claim()
        if repeats {
            return movement.consume(input, mapping: mapping, at: now)
        }
        if input.units == .detents {
            // Match line scrolling: trigger at half a detent, then every full
            // detent. Consume crossings during cooldown without queuing commands.
            guard movement.consume(input, mapping: mapping, roundToNearestStep: true, at: now) > 0 else {
                return 0
            }
        } else {
            movement.discard(on: input.axis)
        }
        return throttle.allowsAction(on: input.axis, at: now) ? 1 : 0
    }
}

extension Scheme.Buttons.Mapping.Action {
    var repeatsWithScrollMovement: Bool {
        switch self {
        case .arg0(.mouseWheelScrollUp), .arg0(.mouseWheelScrollDown),
             .arg0(.mouseWheelScrollLeft), .arg0(.mouseWheelScrollRight),
             .arg1(.mouseWheelScrollUp), .arg1(.mouseWheelScrollDown),
             .arg1(.mouseWheelScrollLeft), .arg1(.mouseWheelScrollRight):
            true
        default:
            false
        }
    }
}

extension Scheme.Buttons.Mapping.Action {
    /// Coalesce scroll impulses so event splitting preserves distance without
    /// allocating or posting one action per step.
    func coalescingScrollSteps(_ count: Int) -> Self {
        func scaled(_ distance: Scheme.Scrolling.Distance) -> Scheme.Scrolling.Distance {
            switch distance {
            case .auto:
                return scaled(.line(3))
            case let .line(value):
                let product = Decimal(value) * Decimal(count)
                let limit = Decimal(Int32.max)
                return .line(NSDecimalNumber(decimal: min(limit, max(-limit, product))).intValue)
            case let .pixel(value):
                return .pixel(value * Decimal(count))
            }
        }
        switch self {
        case .arg0(.mouseWheelScrollUp):
            return .arg1(.mouseWheelScrollUp(scaled(.auto)))
        case .arg0(.mouseWheelScrollDown):
            return .arg1(.mouseWheelScrollDown(scaled(.auto)))
        case .arg0(.mouseWheelScrollLeft):
            return .arg1(.mouseWheelScrollLeft(scaled(.auto)))
        case .arg0(.mouseWheelScrollRight):
            return .arg1(.mouseWheelScrollRight(scaled(.auto)))
        case let .arg1(.mouseWheelScrollUp(distance)):
            return .arg1(.mouseWheelScrollUp(scaled(distance)))
        case let .arg1(.mouseWheelScrollDown(distance)):
            return .arg1(.mouseWheelScrollDown(scaled(distance)))
        case let .arg1(.mouseWheelScrollLeft(distance)):
            return .arg1(.mouseWheelScrollLeft(scaled(distance)))
        case let .arg1(.mouseWheelScrollRight(distance)):
            return .arg1(.mouseWheelScrollRight(scaled(distance)))
        default:
            return self
        }
    }
}
