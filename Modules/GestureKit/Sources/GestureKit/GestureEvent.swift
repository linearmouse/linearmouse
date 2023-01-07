// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import AppKit
import CoreGraphics

public class GestureEvent {
    let cgEvents: [CGEvent]

    internal init(cgEvents: [CGEvent]) {
        self.cgEvents = cgEvents
    }

    public func post(tap: CGEventTapLocation) {
        for cgEvent in cgEvents {
            cgEvent.post(tap: tap)
        }
    }
}
