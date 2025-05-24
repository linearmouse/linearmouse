// MIT License
// Copyright (c) 2021-2025 LinearMouse

class EventType {
    static let all: [CGEventType] = [
        .scrollWheel,
        .leftMouseDown,
        .leftMouseUp,
        .leftMouseDragged,
        .rightMouseDown,
        .rightMouseUp,
        .rightMouseDragged,
        .otherMouseDown,
        .otherMouseUp,
        .otherMouseDragged,
        .keyDown,
        .keyUp,
        .flagsChanged
    ]

    static let mouseMoved: CGEventType = .mouseMoved
}
