// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

final class LogitechHighResolutionWheelNormalizer: EventTransformer {
    enum AxisMode {
        case passthrough
        case lowResolution
    }

    private let verticalMode: AxisMode
    private let horizontalMode: AxisMode
    private let highResolutionWheelMultiplier: (EventTransformerContext) -> Int?
    private let now: () -> TimeInterval

    private var verticalCounter = LogitechHighResolutionWheelScrollCounter()
    private var horizontalCounter = LogitechHighResolutionWheelScrollCounter()

    init(
        verticalMode: AxisMode,
        horizontalMode: AxisMode,
        highResolutionWheelMultiplier: @escaping (EventTransformerContext) -> Int? = {
            $0.device?.highResolutionWheelNormalizationMultiplier
        },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.verticalMode = verticalMode
        self.horizontalMode = horizontalMode
        self.highResolutionWheelMultiplier = highResolutionWheelMultiplier
        self.now = now
    }

    var normalizesAnyAxis: Bool {
        verticalMode != .passthrough || horizontalMode != .passthrough
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel,
              !event.isLinearMouseSyntheticEvent,
              let multiplier = highResolutionWheelMultiplier(context),
              multiplier > 1 else {
            return event
        }

        let view = ScrollWheelEventView(event)
        normalizeVertical(on: view, multiplier: multiplier)
        normalizeHorizontal(on: view, multiplier: multiplier)

        return hasScrollDelta(view) ? event : nil
    }

    private func normalizeVertical(on view: ScrollWheelEventView, multiplier: Int) {
        let unitResolution = LogitechHighResolutionWheelUnitReader.verticalUnitResolution(
            from: view,
            multiplier: multiplier
        )
        let units = unitResolution.units
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
        }
    }

    private func normalizeHorizontal(on view: ScrollWheelEventView, multiplier: Int) {
        let unitResolution = LogitechHighResolutionWheelUnitReader.horizontalUnitResolution(
            from: view,
            multiplier: multiplier
        )
        let units = unitResolution.units
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
        }
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

    private var remainder = 0.0
    private var direction = 0
    private var lastTime: TimeInterval?

    mutating func consume(units: Double, multiplier: Int, now: TimeInterval) -> Int? {
        guard units != 0, multiplier > 1 else {
            return units == 0 ? nil : Int(units.rounded(.toNearestOrAwayFromZero))
        }

        let currentDirection = units > 0 ? 1 : -1
        if let lastTime, now - lastTime > Self.resetInterval {
            remainder = 0
        }
        if direction != 0, currentDirection != direction {
            remainder = 0
        }

        direction = currentDirection
        lastTime = now
        remainder += units

        let multiplier = Double(multiplier)
        guard abs(remainder) * 2 >= multiplier else {
            return nil
        }

        let steps = Int((remainder / multiplier).rounded(.toNearestOrAwayFromZero))
        remainder -= Double(steps) * multiplier

        return steps
    }
}

enum LogitechHighResolutionWheelUnitReader {
    struct UnitResolution {
        var rawUnits: Double
        var acceleratedUnits: Double
        var units: Double
    }

    static func verticalUnits(from view: ScrollWheelEventView, multiplier: Int) -> Double {
        verticalUnitResolution(from: view, multiplier: multiplier).units
    }

    static func verticalUnitResolution(from view: ScrollWheelEventView, multiplier: Int) -> UnitResolution {
        units(
            integerDelta: view.deltaY,
            pointDelta: view.deltaYPt,
            fixedPointDelta: view.deltaYFixedPt,
            ioHidDelta: view.ioHidScrollY,
            signum: view.deltaYSignum,
            multiplier: multiplier
        )
    }

    static func horizontalUnits(from view: ScrollWheelEventView, multiplier: Int) -> Double {
        horizontalUnitResolution(from: view, multiplier: multiplier).units
    }

    static func horizontalUnitResolution(from view: ScrollWheelEventView, multiplier: Int) -> UnitResolution {
        units(
            integerDelta: view.deltaX,
            pointDelta: view.deltaXPt,
            fixedPointDelta: view.deltaXFixedPt,
            ioHidDelta: view.ioHidScrollX,
            signum: view.deltaXSignum,
            multiplier: multiplier
        )
    }

    static func units(
        integerDelta: Int64,
        pointDelta: Double,
        fixedPointDelta: Double,
        ioHidDelta: Double,
        signum: Int64,
        multiplier: Int
    ) -> UnitResolution {
        let direction = eventDirection(
            integerDelta: integerDelta,
            pointDelta: pointDelta,
            fixedPointDelta: fixedPointDelta,
            signum: signum,
            fallbackDelta: ioHidDelta
        )
        guard direction != 0 else {
            return .init(rawUnits: 0, acceleratedUnits: 0, units: 0)
        }

        let rawUnitMagnitude = rawUnits(
            ioHidDelta: ioHidDelta,
            integerDelta: integerDelta,
            pointDelta: pointDelta,
            fixedPointDelta: fixedPointDelta,
            signum: signum,
            multiplier: multiplier
        )
        let accelerationMagnitude = accelerationMagnitude(
            integerDelta: integerDelta,
            pointDelta: pointDelta,
            fixedPointDelta: fixedPointDelta,
            usesIOHIDRawUnits: abs(ioHidDelta) >= 0.5
        )

        return .init(
            rawUnits: direction * rawUnitMagnitude,
            acceleratedUnits: direction * accelerationMagnitude,
            units: direction * max(rawUnitMagnitude, accelerationMagnitude)
        )
    }

    private static func rawUnits(
        ioHidDelta: Double,
        integerDelta: Int64,
        pointDelta: Double,
        fixedPointDelta: Double,
        signum: Int64,
        multiplier: Int
    ) -> Double {
        let ioHidUnits = abs(ioHidDelta)
        if ioHidUnits >= 0.5 {
            return ioHidUnits
        }

        return rawFallbackUnits(
            integerDelta: integerDelta,
            pointDelta: pointDelta,
            fixedPointDelta: fixedPointDelta,
            signum: signum,
            multiplier: multiplier
        )
    }

    private static func rawFallbackUnits(
        integerDelta: Int64,
        pointDelta: Double,
        fixedPointDelta: Double,
        signum: Int64,
        multiplier: Int
    ) -> Double {
        let multiplier = Double(multiplier)

        let fixedPointUnits = fixedPointDelta * multiplier
        if abs(fixedPointUnits) >= 0.5 {
            return abs(fixedPointUnits)
        }

        let pointUnits = pointDelta * multiplier / 10.0
        if abs(pointUnits) >= 0.5 {
            return abs(pointUnits)
        }

        if integerDelta != 0 {
            return abs(Double(integerDelta))
        }

        return abs(Double(signum))
    }

    private static func accelerationMagnitude(
        integerDelta: Int64,
        pointDelta: Double,
        fixedPointDelta: Double,
        usesIOHIDRawUnits: Bool
    ) -> Double {
        guard usesIOHIDRawUnits else {
            return 1
        }

        return max(
            1,
            abs(Double(integerDelta)),
            abs(pointDelta) / 10.0,
            abs(fixedPointDelta)
        )
    }

    private static func eventDirection(
        integerDelta: Int64,
        pointDelta: Double,
        fixedPointDelta: Double,
        signum: Int64,
        fallbackDelta: Double
    ) -> Double {
        if signum != 0 {
            return Double(signum)
        }
        if fixedPointDelta != 0 {
            return fixedPointDelta.sign == .minus ? -1 : 1
        }
        if pointDelta != 0 {
            return pointDelta.sign == .minus ? -1 : 1
        }
        if integerDelta != 0 {
            return Double(integerDelta.signum())
        }
        if fallbackDelta != 0 {
            return fallbackDelta.sign == .minus ? -1 : 1
        }
        return 0
    }
}
