// MIT License
// Copyright (c) 2021-2023 LinearMouse

import CoreGraphics

public extension GestureEvent {
    convenience init?(zoomToggleSource: CGEventSource?) {
        guard let event = CGEvent(source: zoomToggleSource) else {
            return nil
        }

        event.type = .init(nsEventType: .gesture)!
        event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.zoomToggle.rawValue))

        self.init(cgEvents: [event])
    }

    convenience init?(zoomSource: CGEventSource?, phase: CGSGesturePhase, magnification: Double) {
        guard let event = CGEvent(source: zoomSource) else {
            return nil
        }

        event.type = .init(nsEventType: .gesture)!
        event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.zoom.rawValue))
        event.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
        event.setDoubleValueField(.gestureZoomValue, value: magnification)

        self.init(cgEvents: [event])
    }
}
