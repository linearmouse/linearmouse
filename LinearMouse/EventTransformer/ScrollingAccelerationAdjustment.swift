// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class ScrollingAccelerationAdjustment: EventTransformer {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ScrollingAccelerationAdjustment"
    )

    private let acceleration: Scheme.Scrolling.Bidirectional<Decimal>

    init(acceleration: Scheme.Scrolling.Bidirectional<Decimal>) {
        self.acceleration = acceleration
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let scrollWheelEventView = ScrollWheelEventView(event)

        if scrollWheelEventView.deltaYSignum != 0,
           let acceleration = acceleration.vertical?.asTruncatedDouble, acceleration != 1 {
            scrollWheelEventView.scale(factorY: acceleration)
            os_log("deltaY: acceleration=%f", log: Self.log, type: .debug, acceleration)
        }

        if scrollWheelEventView.deltaXSignum != 0,
           let acceleration = acceleration.horizontal?.asTruncatedDouble, acceleration != 1 {
            scrollWheelEventView.scale(factorX: acceleration)
            os_log("deltaX: acceleration=%f", log: Self.log, type: .debug, acceleration)
        }

        return event
    }
}
