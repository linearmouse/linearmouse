// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit

public extension CGEventType {
    init?(nsEventType: NSEvent.EventType) {
        self.init(rawValue: UInt32(nsEventType.rawValue))
    }
}
