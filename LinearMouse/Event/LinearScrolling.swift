// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log

class LinearScrolling: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "LinearScrolling")

    private let scrollLines: Int

    init(scrollLines: Int) {
        self.scrollLines = scrollLines
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)
        guard view.momentumPhase == .none else {
            return nil
        }
        let (continuous, oldValue) = (view.continuous, view.matrixValue)
        let (deltaXSignum, deltaYSignum) = (view.deltaXSignum, view.deltaYSignum)
        view.continuous = false
        view.deltaX = deltaXSignum * Int64(scrollLines)
        view.deltaY = deltaYSignum * Int64(scrollLines)
        os_log("continuous=%{public}@, oldValue=%{public}@, newValue=%{public}@", log: Self.log, type: .debug,
               String(describing: continuous),
               String(describing: oldValue),
               String(describing: view.matrixValue))
        return event
    }
}
