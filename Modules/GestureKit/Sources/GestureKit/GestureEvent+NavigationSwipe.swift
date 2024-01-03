// MIT License
// Copyright (c) 2021-2024 LinearMouse

import CoreGraphics

public extension GestureEvent {
    convenience init?(navigationSwipeSource: CGEventSource?, direction: IOHIDSwipeMask) {
        guard let swipeBeganEvent = CGEvent(source: navigationSwipeSource) else {
            return nil
        }

        guard let swipeEndedEvent = CGEvent(source: navigationSwipeSource) else {
            return nil
        }

        swipeBeganEvent.type = .init(nsEventType: .gesture)!
        swipeBeganEvent.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.navigationSwipe.rawValue))
        swipeBeganEvent.setIntegerValueField(.gesturePhase, value: Int64(CGSGesturePhase.began.rawValue))
        swipeBeganEvent.setIntegerValueField(.gestureSwipeValue, value: Int64(direction.rawValue))

        swipeEndedEvent.type = .init(nsEventType: .gesture)!
        swipeEndedEvent.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.navigationSwipe.rawValue))
        swipeEndedEvent.setIntegerValueField(.gesturePhase, value: Int64(CGSGesturePhase.ended.rawValue))

        self.init(cgEvents: [swipeBeganEvent, swipeEndedEvent])
    }
}
