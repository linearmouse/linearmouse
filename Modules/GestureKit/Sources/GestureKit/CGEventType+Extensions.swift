// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit

public extension CGEventType {
    init?(nsEventType: NSEvent.EventType) {
        self.init(rawValue: UInt32(nsEventType.rawValue))
    }
}
