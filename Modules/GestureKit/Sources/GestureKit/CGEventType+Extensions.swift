// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import AppKit

public extension CGEventType {
    init?(nsEventType: NSEvent.EventType) {
        self.init(rawValue: UInt32(nsEventType.rawValue))
    }
}
