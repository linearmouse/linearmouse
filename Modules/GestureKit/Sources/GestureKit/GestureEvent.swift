//
//  GestureEvent.swift
//
//
//  Created by Jiahao Lu on 2022/6/13.
//

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
