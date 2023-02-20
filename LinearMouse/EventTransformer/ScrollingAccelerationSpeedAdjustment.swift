// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class ScrollingAccelerationSpeedAdjustment: EventTransformer {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ScrollingAccelerationSpeedAdjustment"
    )

    private let acceleration: Scheme.Scrolling.Bidirectional<Decimal>
    private let speed: Scheme.Scrolling.Bidirectional<Decimal>

    init(acceleration: Scheme.Scrolling.Bidirectional<Decimal>,
         speed: Scheme.Scrolling.Bidirectional<Decimal>) {
        self.acceleration = acceleration
        self.speed = speed
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let scrollWheelEventView = ScrollWheelEventView(event)
        let deltaYSignum = scrollWheelEventView.deltaYSignum
        let deltaXSignum = scrollWheelEventView.deltaXSignum

        if deltaYSignum != 0,
           let acceleration = acceleration.vertical?.asTruncatedDouble, acceleration != 1 {
            scrollWheelEventView.scale(factorY: acceleration)
            os_log("deltaY: acceleration=%f", log: Self.log, type: .debug, acceleration)
        }

        if deltaXSignum != 0,
           let acceleration = acceleration.horizontal?.asTruncatedDouble, acceleration != 1 {
            scrollWheelEventView.scale(factorX: acceleration)
            os_log("deltaX: acceleration=%f", log: Self.log, type: .debug, acceleration)
        }

        if deltaYSignum != 0,
           let speed = speed.vertical?.asTruncatedDouble, speed != 0 {
            let targetPt = scrollWheelEventView.deltaYPt + Double(deltaYSignum) * speed
            scrollWheelEventView.deltaY = deltaYSignum * max(1, Int64(abs(targetPt) / 10))
            scrollWheelEventView.deltaYPt = targetPt
            scrollWheelEventView.deltaYFixedPt = targetPt / 10
            os_log("deltaY: speed=%f", log: Self.log, type: .debug, speed)
        }

        if deltaXSignum != 0,
           let speed = speed.horizontal?.asTruncatedDouble, speed != 0 {
            let targetPt = scrollWheelEventView.deltaXPt + Double(deltaXSignum) * speed
            scrollWheelEventView.deltaX = deltaXSignum * max(1, Int64(abs(targetPt) / 10))
            scrollWheelEventView.deltaXPt = targetPt
            scrollWheelEventView.deltaXFixedPt = targetPt / 10
            os_log("deltaX: speed=%f", log: Self.log, type: .debug, speed)
        }

        os_log("newValue=%@", log: Self.log, type: .debug, String(describing: scrollWheelEventView.matrixValue))

        return event
    }
}
