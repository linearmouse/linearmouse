// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// One normalized representation of movement; phase availability is independent
/// of its resolution. Units affect scroll output, never command throttling.
struct ScrollInput {
    enum Axis: Hashable {
        case horizontal, vertical
    }

    enum Units: Equatable {
        case detents, points, lines

        var threshold: Double {
            self == .points ? 8 : 1
        }
    }

    var axis: Axis
    var delta: Double
    var units: Units
    var hasPhase = false
}

extension ScrollInput {
    static func read(
        from view: ScrollWheelEventView,
        highResolutionMultiplier: Int?,
        axis: Axis? = nil
    ) -> Self? {
        /// Choose one representation, never add line and pixel deltas together.
        func delta(integer: Int64, fixed: Double, points: Double) -> Double {
            if view.continuous {
                return points
            }
            if fixed != 0 {
                return fixed
            }
            if integer != 0 {
                return Double(integer)
            }
            // The same point-to-line fallback used by high-resolution scrolling.
            return points / 10
        }
        let x = delta(integer: view.deltaX, fixed: view.deltaXFixedPt, points: view.deltaXPt)
        let y = delta(integer: view.deltaY, fixed: view.deltaYFixedPt, points: view.deltaYPt)
        guard x.isFinite, y.isFinite, x != 0 || y != 0 else {
            return nil
        }
        let horizontal = axis.map { $0 == .horizontal } ?? (abs(x) > abs(y))
        let value = horizontal ? x : y
        guard value != 0 else {
            return nil
        }
        let axis: ScrollInput.Axis = horizontal ? .horizontal : .vertical
        if view.continuous || view.scrollPhase != nil {
            return .init(
                axis: axis,
                delta: value,
                units: view.continuous ? .points : .lines,
                hasPhase: view.scrollPhase != nil
            )
        }
        // Side/tilt wheels have no portable detent or touch-boundary metadata.
        // Treat their unphased stream as a movement, independent of mouse brand.
        if horizontal {
            return .init(axis: axis, delta: value, units: .lines)
        }
        if let multiplier = highResolutionMultiplier, multiplier > 1 {
            let resolution = LogitechHighResolutionWheelUnitReader.verticalUnitResolution(
                from: view,
                multiplier: multiplier
            )
            // Page-scroll acceleration must not multiply action impulses.
            // rawUnits already carries a sign; use only its magnitude with the selected delta's direction.
            let units = (value > 0 ? 1.0 : -1.0) * abs(resolution.rawUnits) / Double(multiplier)
            return .init(axis: axis, delta: units, units: .detents)
        }
        // Preserve the legacy vertical wheel's one-impulse-per-event behavior.
        // Its accelerated line delta is not a reliable physical detent count.
        return .init(axis: axis, delta: value > 0 ? 1 : -1, units: .detents)
    }
}
