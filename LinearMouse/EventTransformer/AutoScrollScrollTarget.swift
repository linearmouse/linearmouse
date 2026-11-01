// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

/// Delivers Auto Scroll output straight to the window under the anchor, so
/// scrolling continues after the pointer leaves that window.
///
/// A session-tap scroll goes to whatever is under the cursor, and giving it a
/// location warps the cursor there. A pid-targeted event does neither, but an
/// app only routes it to a view once it carries a window number (field 51) and
/// a window-local location; without them AppKit drops it.
struct AutoScrollScrollTarget: Equatable {
    let pid: pid_t
    let windowID: CGWindowID
    /// The anchor in global display coordinates (top-left origin).
    let location: CGPoint
    /// The anchor relative to the window's top-left corner.
    let windowLocation: CGPoint

    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void

    private static let setWindowLocation: SetWindowLocation? = {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation") else {
            return nil
        }
        return unsafeBitCast(address, to: SetWindowLocation.self)
    }()

    private static let windowNumberField = CGEventField(rawValue: 51)
    private static let windowUnderPointerFields: [CGEventField] = [
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent
    ]

    static func resolve(at point: CGPoint) -> Self? {
        guard setWindowLocation != nil, windowNumberField != nil,
              let hit = WindowFocus.shared.windowHit(at: point),
              hit.target.pid != getpid(),
              // Accessory and agent apps (menu bar panels, HUDs) may never have
              // been active and can ignore pid-targeted mouse events. Keep the
              // cursor-following path for them.
              NSRunningApplication(processIdentifier: hit.target.pid)?.activationPolicy == .regular else {
            return nil
        }

        return .init(
            pid: hit.target.pid,
            windowID: hit.target.windowID,
            location: point,
            windowLocation: hit.windowLocation
        )
    }

    func post(_ event: CGEvent) {
        guard let setWindowLocation = Self.setWindowLocation,
              let windowNumberField = Self.windowNumberField else {
            return
        }

        event.location = location
        setWindowLocation(event, windowLocation)
        event.setIntegerValueField(windowNumberField, value: Int64(windowID))
        for field in Self.windowUnderPointerFields {
            event.setIntegerValueField(field, value: Int64(windowID))
        }
        event.postToPid(pid)
    }
}
