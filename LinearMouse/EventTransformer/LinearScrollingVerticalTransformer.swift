// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

class LinearScrollingVerticalTransformer: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "LinearScrollingVertical")

    private let distance: Scheme.Scrolling.Distance
    private let highResolutionWheelMultiplier: (EventTransformerContext) -> Int?
    private let now: () -> TimeInterval
    private var highResolutionWheelCounter = LogitechHighResolutionWheelScrollCounter()

    init(
        distance: Scheme.Scrolling.Distance,
        highResolutionWheelMultiplier: @escaping (EventTransformerContext) -> Int? = {
            $0.device?.highResolutionWheelNormalizationMultiplier
        },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.distance = distance
        self.highResolutionWheelMultiplier = highResolutionWheelMultiplier
        self.now = now
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        if event.isLinearMouseSyntheticEvent {
            return event
        }

        if case .auto = distance {
            return event
        }

        let view = ScrollWheelEventView(event)

        guard view.deltaYSignum != 0 else {
            return event
        }

        guard view.momentumPhase == .none else {
            return nil
        }

        let (continuous, oldValue) = (view.continuous, view.matrixValue)
        switch distance {
        case .auto:
            return event

        case let .line(value):
            guard let normalizedUnits = lowResolutionUnits(from: view, in: context) else {
                return nil
            }

            view.continuous = false
            view.deltaY = Int64(normalizedUnits * value)
            view.deltaX = 0

        case let .pixel(value):
            let pixelValue = highResolutionPixelUnits(from: view, in: context) * value.asTruncatedDouble

            view.continuous = true
            view.deltaYPt = pixelValue
            view.deltaYFixedPt = pixelValue
            view.deltaXPt = 0
            view.deltaXFixedPt = 0
        }

        os_log(
            "continuous=%{public}@, oldValue=%{public}@, newValue=%{public}@",
            log: Self.log,
            type: .info,
            String(describing: continuous),
            String(describing: oldValue),
            String(describing: view.matrixValue)
        )

        return event
    }

    private func lowResolutionUnits(from view: ScrollWheelEventView, in context: EventTransformerContext) -> Int? {
        guard let multiplier = highResolutionWheelMultiplier(context),
              multiplier > 1 else {
            return Int(view.deltaYSignum)
        }

        return highResolutionWheelCounter.consume(
            units: LogitechHighResolutionWheelUnitReader.verticalUnitResolution(
                from: view,
                multiplier: multiplier
            )
            .rawUnits,
            multiplier: multiplier,
            now: now()
        )
    }

    private func highResolutionPixelUnits(
        from view: ScrollWheelEventView,
        in context: EventTransformerContext
    ) -> Double {
        guard let multiplier = highResolutionWheelMultiplier(context),
              multiplier > 1 else {
            return Double(view.deltaYSignum)
        }

        return LogitechHighResolutionWheelUnitReader.verticalUnitResolution(
            from: view,
            multiplier: multiplier
        )
        .rawUnits
        / Double(multiplier)
    }
}
