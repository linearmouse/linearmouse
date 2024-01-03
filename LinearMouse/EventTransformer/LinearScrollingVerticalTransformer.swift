// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation
import os.log

class LinearScrollingVerticalTransformer: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "LinearScrollingVertical")

    private let distance: Scheme.Scrolling.Distance

    init(distance: Scheme.Scrolling.Distance) {
        self.distance = distance
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
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
        let deltaYSignum = view.deltaYSignum

        switch distance {
        case .auto:
            return event

        case let .line(value):
            view.continuous = false
            view.deltaY = deltaYSignum * Int64(value)
            view.deltaX = 0

        case let .pixel(value):
            view.continuous = true
            view.deltaYPt = Double(deltaYSignum) * value.asTruncatedDouble
            view.deltaYFixedPt = Double(deltaYSignum) * value.asTruncatedDouble
            view.deltaXPt = 0
            view.deltaXFixedPt = 0
        }

        os_log("continuous=%{public}@, oldValue=%{public}@, newValue=%{public}@", log: Self.log, type: .info,
               String(describing: continuous),
               String(describing: oldValue),
               String(describing: view.matrixValue))

        return event
    }
}
