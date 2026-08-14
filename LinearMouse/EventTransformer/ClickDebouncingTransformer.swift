// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

class ClickDebouncingTransformer: EventTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ClickDebouncing")

    private let button: CGMouseButton
    private let timeout: TimeInterval
    private let resetTimerOnMouseUp: Bool
    private let nowInNanoseconds: () -> UInt64

    init(
        for button: CGMouseButton,
        timeout: TimeInterval,
        resetTimerOnMouseUp: Bool,
        nowInNanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.button = button
        self.timeout = timeout
        self.resetTimerOnMouseUp = resetTimerOnMouseUp
        self.nowInNanoseconds = nowInNanoseconds
    }

    private var mouseDownEventType: CGEventType {
        button.fixedCGEventType(of: .leftMouseDown)
    }

    private var mouseUpEventType: CGEventType {
        button.fixedCGEventType(of: .leftMouseUp)
    }

    private var lastClickedAtInNanoseconds: UInt64 = 0
    private var lastReleasedAtInNanoseconds: UInt64 = 0

    /// Forwarded presses that have not been closed by a forwarded release yet.
    /// A counter rather than a flag: event streams from other applications are
    /// not guaranteed to alternate down/up.
    private var unreleasedPressCount = 0

    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
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
                os_log(
                    "Mouse down ignored because interval since last click %{public}f <= %{public}f",
                    log: Self.log,
                    type: .info,
                    intervalSinceLastClick,
                    timeout
                )
                return nil
            }
            unreleasedPressCount += 1
            return event
        case mouseUpEventType:
            // Never swallow the release that closes a forwarded press: the app
            // would see a mouse down without its mouse up and treat the button
            // as stuck. Only releases with no forwarded press to close are
            // bounce artifacts and may be dropped inside the window.
            let intervalSinceLastRelease = intervalSinceLastRelease
            touchLastReleasedAt()
            // A suppressed release is still a physical contact break: the next
            // bounce-down must land inside the press window, so the press timer
            // re-arms on every release, forwarded or not — the same sliding
            // behavior the press side applies to suppressed presses.
            if resetTimerOnMouseUp {
                touchLastClickedAt()
            }
            if intervalSinceLastRelease <= timeout, unreleasedPressCount == 0 {
                os_log(
                    "Mouse up ignored because interval since last release %{public}f <= %{public}f",
                    log: Self.log,
                    type: .info,
                    intervalSinceLastRelease,
                    timeout
                )
                return nil
            }
            if unreleasedPressCount > 0 {
                unreleasedPressCount -= 1
            }
            return event
        default:
            break
        }

        return event
    }

    private func touchLastClickedAt() {
        lastClickedAtInNanoseconds = nowInNanoseconds()
    }

    private func touchLastReleasedAt() {
        lastReleasedAtInNanoseconds = nowInNanoseconds()
    }

    private var intervalSinceLastClick: TimeInterval {
        let nanosecondsPerSecond = 1e9
        return Double(nowInNanoseconds() - lastClickedAtInNanoseconds) / nanosecondsPerSecond
    }

    private var intervalSinceLastRelease: TimeInterval {
        let nanosecondsPerSecond = 1e9
        return Double(nowInNanoseconds() - lastReleasedAtInNanoseconds) / nanosecondsPerSecond
    }
}
