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

    var continuous: Bool {
        get { event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 }
        set { event.setIntegerValueField(.scrollWheelEventIsContinuous, value: newValue ? 1 : 0) }
    }

    var momentumPhase: CGMomentumScrollPhase {
        .init(rawValue: UInt32(event.getIntegerValueField(.scrollWheelEventMomentumPhase))) ?? .none
    }

    var deltaX: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis2) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: newValue) }
    }

    var deltaXFixedPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) }
        set { event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: newValue) }
    }

    var deltaXPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) }
        set { event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: newValue) }
    }

    var deltaY: Int64 {
        get { event.getIntegerValueField(.scrollWheelEventDeltaAxis1) }
        set { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: newValue) }
    }

    var deltaYFixedPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) }
        set { event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: newValue) }
    }

    var deltaYPt: Double {
        get { event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) }
        set { event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: newValue) }
    }

    func swapXY() {
        (deltaX, deltaY, deltaXFixedPt, deltaYFixedPt, deltaXPt, deltaYPt) =
        (deltaY, deltaX, deltaYFixedPt, deltaXFixedPt, deltaYPt, deltaXPt)
    }

    func negate() {
        (deltaY, deltaYFixedPt, deltaYPt) = (-deltaY, -deltaYFixedPt, -deltaYPt)
    }

    func scale(factor: Double) {
        let scaleInt = { (value: Int64, factor: Double, minAbs: Int64) -> Int64 in
            value.signum() * max(minAbs, abs(Int64((Double(value) * factor).rounded())))
        }
        (deltaX, deltaXFixedPt, deltaXPt) = (scaleInt(deltaX, factor, 1), deltaXFixedPt * factor, deltaXPt * factor)
        (deltaY, deltaYFixedPt, deltaYPt) = (scaleInt(deltaY, factor, 1), deltaYFixedPt * factor, deltaYPt * factor)
    }
}
