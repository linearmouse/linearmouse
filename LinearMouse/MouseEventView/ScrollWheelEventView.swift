//
//  WheelEventView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class ScrollWheelEventView: MouseEventView {
    override init(_ event: CGEvent) {
        assert(event.type == .scrollWheel)
        super.init(event)
    }

    var deltaX: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis2) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: newValue) }
    }

    var deltaY: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis1) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: newValue) }
    }

    func swapDeltaXY() {
        (deltaX, deltaY) = (deltaY, deltaX)
    }
}
