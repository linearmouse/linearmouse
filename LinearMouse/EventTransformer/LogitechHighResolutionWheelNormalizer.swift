// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

final class LogitechHighResolutionWheelNormalizer: EventTransformer {
    enum AxisMode {
        case passthrough
        case lowResolution
        case smoothed
    }

    private static let lineStepInPixels = 36.0

    private let verticalMode: AxisMode
    private let horizontalMode: AxisMode
    private let multiplier: () -> Int?
    private let now: () -> TimeInterval

    private var verticalCounter = LogitechHighResolutionWheelScrollCounter()
    private var horizontalCounter = LogitechHighResolutionWheelScrollCounter()

    init(
        verticalMode: AxisMode,
        horizontalMode: AxisMode,
        multiplier: @escaping () -> Int?,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.verticalMode = verticalMode
        self.horizontalMode = horizontalMode
        self.multiplier = multiplier
        self.now = now
    }

    var normalizesAnyAxis: Bool {
        verticalMode != .passthrough || horizontalMode != .passthrough
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel,
              !event.isLinearMouseSyntheticEvent,
              let multiplier = multiplier(),
              multiplier > 1 else {
            return event
        }

        let view = ScrollWheelEventView(event)
        normalizeVertical(on: view, multiplier: multiplier)
        normalizeHorizontal(on: view, multiplier: multiplier)

        return hasScrollDelta(view) ? event : nil
    }

    private func normalizeVertical(on view: ScrollWheelEventView, multiplier: Int) {
        let units = signedVerticalUnits(from: view)
        guard units != 0 else {
            return
        }

        switch verticalMode {
        case .passthrough:
            return

        case .lowResolution:
            guard let steps = verticalCounter.consume(units: units, multiplier: multiplier, now: now()) else {
                zeroVertical(on: view)
                return
            }
            setLowResolutionVertical(steps, on: view)

        case .smoothed:
            setContinuousVertical(Double(units) * Self.lineStepInPixels / Double(multiplier), on: view)
        }
    }

    private func normalizeHorizontal(on view: ScrollWheelEventView, multiplier: Int) {
        let units = signedHorizontalUnits(from: view)
        guard units != 0 else {
            return
        }

        switch horizontalMode {
        case .passthrough:
            return

        case .lowResolution:
            guard let steps = horizontalCounter.consume(units: units, multiplier: multiplier, now: now()) else {
                zeroHorizontal(on: view)
                return
            }
            setLowResolutionHorizontal(steps, on: view)

        case .smoothed:
            setContinuousHorizontal(Double(units) * Self.lineStepInPixels / Double(multiplier), on: view)
        }
    }

    private func signedVerticalUnits(from view: ScrollWheelEventView) -> Int {
        if view.deltaY != 0 {
            return Int(view.deltaY)
        }

        return Int(view.deltaYSignum)
    }

    private func signedHorizontalUnits(from view: ScrollWheelEventView) -> Int {
        if view.deltaX != 0 {
            return Int(view.deltaX)
        }

        return Int(view.deltaXSignum)
    }

    private func setLowResolutionVertical(_ steps: Int, on view: ScrollWheelEventView) {
        view.deltaY = Int64(steps)
        view.deltaYPt = Double(steps) * 10
        view.deltaYFixedPt = Double(steps)
        view.ioHidScrollY = Double(steps)
    }

    private func setLowResolutionHorizontal(_ steps: Int, on view: ScrollWheelEventView) {
        view.deltaX = Int64(steps)
        view.deltaXPt = Double(steps) * 10
        view.deltaXFixedPt = Double(steps)
        view.ioHidScrollX = Double(steps)
    }

    private func setContinuousVertical(_ pixels: Double, on view: ScrollWheelEventView) {
        view.continuous = true
        view.deltaY = Int64((pixels / Self.lineStepInPixels).rounded(.towardZero))
        view.deltaYPt = pixels
        view.deltaYFixedPt = pixels
        view.ioHidScrollY = pixels
    }

    private func setContinuousHorizontal(_ pixels: Double, on view: ScrollWheelEventView) {
        view.continuous = true
        view.deltaX = Int64((pixels / Self.lineStepInPixels).rounded(.towardZero))
        view.deltaXPt = pixels
        view.deltaXFixedPt = pixels
        view.ioHidScrollX = pixels
    }

    private func zeroVertical(on view: ScrollWheelEventView) {
        view.deltaY = 0
        view.deltaYPt = 0
        view.deltaYFixedPt = 0
        view.ioHidScrollY = 0
    }

    private func zeroHorizontal(on view: ScrollWheelEventView) {
        view.deltaX = 0
        view.deltaXPt = 0
        view.deltaXFixedPt = 0
        view.ioHidScrollX = 0
    }

    private func hasScrollDelta(_ view: ScrollWheelEventView) -> Bool {
        view.deltaX != 0 || view.deltaY != 0 ||
            view.deltaXPt != 0 || view.deltaYPt != 0 ||
            view.deltaXFixedPt != 0 || view.deltaYFixedPt != 0 ||
            view.ioHidScrollX != 0 || view.ioHidScrollY != 0
    }
}

struct LogitechHighResolutionWheelScrollCounter {
    private static let resetInterval: TimeInterval = 1

    private var remainder = 0
    private var direction = 0
    private var lastTime: TimeInterval?

    mutating func consume(units: Int, multiplier: Int, now: TimeInterval) -> Int? {
        guard units != 0, multiplier > 1 else {
            return units == 0 ? nil : units
        }

        let currentDirection = units.signum()
        if let lastTime, now - lastTime > Self.resetInterval {
            remainder = 0
        }
        if direction != 0, currentDirection != direction {
            remainder = 0
        }

        direction = currentDirection
        lastTime = now
        remainder += units

        guard abs(remainder) * 2 >= multiplier else {
            return nil
        }

        var steps = remainder / multiplier
        if steps == 0 {
            steps = currentDirection
        }
        remainder -= steps * multiplier

        return steps
    }
}
