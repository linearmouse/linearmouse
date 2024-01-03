// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation
import os.log

class LinearScrollingHorizontalTransformer: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "LinearScrollingHorizontal")

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

        guard view.deltaXSignum != 0 else {
            return event
        }

        guard view.momentumPhase == .none else {
            return nil
        }

        let (continuous, oldValue) = (view.continuous, view.matrixValue)
        let deltaXSignum = view.deltaXSignum

        switch distance {
        case .auto:
            return event

        case let .line(value):
            view.continuous = false
            view.deltaX = deltaXSignum * Int64(value)
            view.deltaY = 0

        case let .pixel(value):
            view.continuous = true
            view.deltaXPt = Double(deltaXSignum) * value.asTruncatedDouble
            view.deltaXFixedPt = Double(deltaXSignum) * value.asTruncatedDouble
            view.deltaYPt = 0
            view.deltaYFixedPt = 0
        }

        os_log("continuous=%{public}@, oldValue=%{public}@, newValue=%{public}@", log: Self.log, type: .info,
               String(describing: continuous),
               String(describing: oldValue),
               String(describing: view.matrixValue))

        return event
    }
}
