// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import os.log

class ClickDebouncingTransformer: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ClickDebouncing")

    private let button: CGMouseButton
    private let timeout: TimeInterval
    private let resetTimerOnMouseUp: Bool

    init(for button: CGMouseButton, timeout: TimeInterval, resetTimerOnMouseUp: Bool) {
        self.button = button
        self.timeout = timeout
        self.resetTimerOnMouseUp = resetTimerOnMouseUp
    }

    private var mouseDownEventType: CGEventType { button.fixedCGEventType(of: .leftMouseDown) }

    private var mouseUpEventType: CGEventType { button.fixedCGEventType(of: .leftMouseUp) }

    enum State {
        case unknown, waitForDown, waitForUp
    }

    private var state: State = .unknown
    private var lastClickedAt: Date = .distantPast

    func transform(_ event: CGEvent) -> CGEvent? {
        guard [mouseDownEventType, mouseUpEventType].contains(event.type) else {
            return event
        }
        let mouseEventView = MouseEventView(event)
        guard mouseEventView.mouseButton == button else {
            return event
        }

        switch event.type {
        case mouseDownEventType:
            let intervalSinceLastClick = intervalSinceLastClick
            touchLastClickedAt()
            if intervalSinceLastClick <= timeout {
                state = .waitForDown
                os_log("Mouse down ignored because interval since last click %{public}f <= %{public}f",
                       log: Self.log,
                       type: .debug,
                       intervalSinceLastClick,
                       timeout)
                return nil
            }
            state = .waitForUp
            return event
        case mouseUpEventType:
            if state == .waitForDown {
                os_log("Mouse up ignored because last mouse down ignored",
                       log: Self.log,
                       type: .debug,
                       intervalSinceLastClick,
                       timeout)
                return nil
            }
            if resetTimerOnMouseUp {
                touchLastClickedAt()
            }
            state = .waitForDown
            return event
        default:
            break
        }

        return event
    }

    private func touchLastClickedAt() {
        lastClickedAt = .init()
    }

    private var intervalSinceLastClick: TimeInterval { -lastClickedAt.timeIntervalSinceNow }
}