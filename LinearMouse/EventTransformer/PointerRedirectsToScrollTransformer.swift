// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

class PointerRedirectsToScrollTransformer: EventTransformer {
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard event.type == .mouseMoved else {
            return event
        }

        Self.redirectToScroll(event)
        return nil
    }

    /// Posts a scroll event for the pointer movement in `event` and keeps the cursor in place.
    static func redirectToScroll(_ event: CGEvent) {
        // Despite making this function return nil, the mouseMoved event
        // still causes the cursor to move, so we need to manually move
        // the cursor to maintain a fixed position during scrolling.
        CGWarpMouseCursorPosition(event.location)

        let deltaX = event.getDoubleValueField(.mouseEventDeltaX)
        let deltaY = event.getDoubleValueField(.mouseEventDeltaY)
        let scrollX = -deltaX
        let scrollY = -deltaY

        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(scrollY),
            wheel2: Int32(scrollX),
            wheel3: 0
        ) {
            scrollEvent.post(tap: .cghidEventTap)
        }
    }
}
