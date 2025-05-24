// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Foundation

class PointerRedirectsToScrollTransformer: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .mouseMoved else {
            return event
        }

        // Despite making this function return nil, the mouseMoved event
        // still causes the cursor to move, so we need to manually move
        // the cursor to maintain a fixed position during scrolling.
        CGWarpMouseCursorPosition(topLeftScreenCoordinates())

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

        return nil
    }

    private func topLeftScreenCoordinates() -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return mouseLocation }
        return CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)
    }
}
