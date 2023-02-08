// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class DiscreteScrolling: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DiscreteScrolling")

    private let discrete: Scheme.Scrolling.Bidirectional<Bool>

    init(discrete: Scheme.Scrolling.Bidirectional<Bool>) {
        self.discrete = discrete
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let scrollWheelEventView = ScrollWheelEventView(event)

        if scrollWheelEventView.deltaYSignum != 0 {
            if discrete.vertical == true {
                scrollWheelEventView.deltaY = scrollWheelEventView.deltaY
                os_log("deltaY=%d", log: Self.log, type: .debug, scrollWheelEventView.deltaY)
            }
        } else {
            if discrete.horizontal == true {
                scrollWheelEventView.deltaX = scrollWheelEventView.deltaX
                os_log("deltaX=%d", log: Self.log, type: .debug, scrollWheelEventView.deltaX)
            }
        }

        return event
    }
}
