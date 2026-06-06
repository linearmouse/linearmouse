// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics

public extension GestureEvent {
    convenience init?(
        scrollSource: CGEventSource?,
        phase: CGSGesturePhase,
        deltaX: Double,
        deltaY: Double,
        flags: CGEventFlags = []
    ) {
        guard let event = CGEvent(source: scrollSource) else {
            return nil
        }

        event.type = .init(nsEventType: .gesture)!
        event.flags = flags
        event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.scroll.rawValue))
        event.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
        event.setIntegerValueField(.scrollGestureFlagBits, value: 1)
        event.setDoubleValueField(.gestureScrollX, value: deltaX)
        event.setDoubleValueField(.gestureScrollY, value: deltaY)

        self.init(cgEvents: [event])
    }

    convenience init?(
        scrollSeriesSource: CGEventSource?,
        started: Bool,
        flags: CGEventFlags = []
    ) {
        guard let event = CGEvent(source: scrollSeriesSource) else {
            return nil
        }

        event.type = .init(nsEventType: .gesture)!
        event.flags = flags
        event.setIntegerValueField(
            .gestureHIDType,
            value: Int64((started ? IOHIDEventType.gestureStarted : .gestureEnded).rawValue)
        )
        event.setIntegerValueField(
            .gestureStartEndSeriesType,
            value: Int64(IOHIDEventType.scroll.rawValue)
        )

        self.init(cgEvents: [event])
    }
}
