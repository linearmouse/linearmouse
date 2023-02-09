// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class AcceleratedScrolling: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AcceleratedScrolling")

    private let acceleration: Scheme.Scrolling.Bidirectional<Decimal>
    private let speed: Scheme.Scrolling.Bidirectional<Decimal>

    init(acceleration: Scheme.Scrolling.Bidirectional<Decimal>, speed: Scheme.Scrolling.Bidirectional<Decimal>) {
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
        if scrollWheelEventView.deltaYSignum != 0 {
            scrollWheelEventView.scale(factorY: acceleration.vertical?.asTruncatedDouble ?? 1)
            let ptIncrement = speed.vertical?.asTruncatedDouble ?? 0
            let fixedPtIncrement = ptIncrement / 10
            scrollWheelEventView.deltaYPt += Double(deltaYSignum) * ptIncrement
            scrollWheelEventView.deltaYFixedPt += Double(deltaYSignum) * fixedPtIncrement
        }
        if scrollWheelEventView.deltaXSignum != 0 {
            scrollWheelEventView.scale(factorX: acceleration.horizontal?.asTruncatedDouble ?? 1)
        }

        return event
    }
}
