//
//  EventView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class MouseEventView {
    let event: CGEvent

    init(_ event: CGEvent) {
        self.event = event
    }

    var mouseButton: CGMouseButton? {
        guard let mouseButtonNumber = UInt32(exactly: event.getIntegerValueField(.mouseEventButtonNumber)) else {
            return nil
        }
        return CGMouseButton(rawValue: mouseButtonNumber)!
    }
}
