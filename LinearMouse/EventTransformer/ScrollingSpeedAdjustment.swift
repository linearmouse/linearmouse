// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class ScrollingSpeedAdjustment: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ScrollingSpeedAdjustment")

    private let speed: Scheme.Scrolling.Bidirectional<Decimal>

    init(speed: Scheme.Scrolling.Bidirectional<Decimal>) {
        self.speed = speed
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let scrollWheelEventView = ScrollWheelEventView(event)
        let deltaYSignum = scrollWheelEventView.deltaYSignum
        let deltaXSignum = scrollWheelEventView.deltaXSignum

        if scrollWheelEventView.deltaYSignum != 0,
           let speed = speed.vertical?.asTruncatedDouble, speed != 0 {
            scrollWheelEventView.deltaYPt += Double(deltaYSignum) * speed
            scrollWheelEventView.deltaYFixedPt += Double(deltaYSignum) * (speed / 10)
            os_log("deltaY: speed=%f", log: Self.log, type: .debug, speed)
        }

        if scrollWheelEventView.deltaXSignum != 0,
           let speed = speed.horizontal?.asTruncatedDouble, speed != 0 {
            scrollWheelEventView.deltaXPt += Double(deltaXSignum) * speed
            scrollWheelEventView.deltaXFixedPt += Double(deltaXSignum) * (speed / 10)
            os_log("deltaX: speed=%f", log: Self.log, type: .debug, speed)
        }

        return event
    }
}
