// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class DebounceClicks: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "DebounceClicks")

    private let interval: TimeInterval

    private var lastClickedButton: CGMouseButton?
    private var lastClickedAt: Date = .distantPast
    private var ignoreNextUp = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    private var mouseDownEventTypes: [CGEventType] {
        [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    }

    private var mouseUpEventTypes: [CGEventType] {
        [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard mouseDownEventTypes.contains(event.type) || mouseUpEventTypes.contains(event.type) else {
            return event
        }

        let mouseEventView = MouseEventView(event)
        guard let mouseButton = mouseEventView.mouseButton else {
            return event
        }
        if mouseDownEventTypes.contains(event.type) {
            let (lastClickedButton, lastClickedAt) = (lastClickedButton, lastClickedAt)
            self.lastClickedButton = mouseButton
            self.lastClickedAt = .init()
            ignoreNextUp = false
            if mouseEventView.mouseButton == lastClickedButton,
               -lastClickedAt.timeIntervalSinceNow < interval {
                ignoreNextUp = true
                os_log("Mouse down ignored, interval = %f < %f",
                       log: Self.log,
                       type: .debug,
                       -lastClickedAt.timeIntervalSinceNow,
                       interval)
                return nil
            }
            return event
        } else {
            let ignoreNextUp = ignoreNextUp
            self.ignoreNextUp = false
            if mouseEventView.mouseButton == lastClickedButton, ignoreNextUp {
                os_log("Mouse up ignored", log: Self.log, type: .debug)
                return nil
            }
            return event
        }
    }
}
