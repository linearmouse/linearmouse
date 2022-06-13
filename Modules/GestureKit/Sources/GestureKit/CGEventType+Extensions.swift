//
//  CGEventType+Extensions.swift
//  
//
//  Created by Jiahao Lu on 2022/6/13.
//

import AppKit

public extension CGEventType {
    init?(nsEventType: NSEvent.EventType) {
        self.init(rawValue: UInt32(nsEventType.rawValue))
    }
}
