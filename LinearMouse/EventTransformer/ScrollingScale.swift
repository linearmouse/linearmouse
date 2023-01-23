// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class ScrollingScale: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ScrollingScale")

    private let scale: Scheme.Scrolling.Bidirectional<Decimal>

    init(scale: Scheme.Scrolling.Bidirectional<Decimal>) {
        self.scale = scale
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)
        view.scale(factorX: scale.horizontal?.asTruncatedDouble ?? 1, factorY: scale.vertical?.asTruncatedDouble ?? 1)

        os_log("scaleX=%@, scaleY=%@", log: Self.log, type: .debug,
               String(describing: scale.horizontal),
               String(describing: scale.vertical))

        return event
    }
}
