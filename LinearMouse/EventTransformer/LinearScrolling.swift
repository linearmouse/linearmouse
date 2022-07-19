// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log

class LinearScrolling: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "LinearScrolling")

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
        guard view.momentumPhase == .none else {
            return nil
        }
        let (continuous, oldValue) = (view.continuous, view.matrixValue)
        let (deltaXSignum, deltaYSignum) = (view.deltaXSignum, view.deltaYSignum)

        switch distance {
        case .auto:
            return event

        case let .line(value):
            view.continuous = false
            view.deltaX = deltaXSignum * Int64(value)
            view.deltaY = deltaYSignum * Int64(value)

        case let .pixel(value):
            view.continuous = true
            view.deltaXPt = Double(deltaXSignum) * value.asTruncatedDouble
            view.deltaYPt = Double(deltaYSignum) * value.asTruncatedDouble
            view.deltaXFixedPt = Double(deltaXSignum) * value.asTruncatedDouble
            view.deltaYFixedPt = Double(deltaYSignum) * value.asTruncatedDouble
        }

        os_log("continuous=%{public}@, oldValue=%{public}@, newValue=%{public}@", log: Self.log, type: .debug,
               String(describing: continuous),
               String(describing: oldValue),
               String(describing: view.matrixValue))

        return event
    }
}
