// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation
import os.log
import SceneKit

class ScrollWheelEventView: MouseEventView {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ScrollWheelEventView")

    private let ioHidEvent: IOHIDEvent?

    override init(_ event: CGEvent) {
        assert(event.type == .scrollWheel)
        ioHidEvent = CGEventCopyIOHIDEvent(event)
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

    var deltaXSignum: Int64 {
        continuous ? Int64(sign(deltaXPt)) : deltaX.signum()
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

    var deltaYSignum: Int64 {
        continuous ? Int64(sign(deltaYPt)) : deltaY.signum()
    }

    var ioHidScrollX: Double {
        get {
            guard let ioHidEvent = ioHidEvent else {
                return 0
            }
            return IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX)
        }
        set {
            guard let ioHidEvent = ioHidEvent else {
                return
            }
            return IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX, newValue)
        }
    }

    var ioHidScrollY: Double {
        get {
            guard let ioHidEvent = ioHidEvent else {
                return 0
            }
            return IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY)
        }
        set {
            guard let ioHidEvent = ioHidEvent else {
                return
            }
            return IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY, newValue)
        }
    }

    var matrixValue: double2x4 {
        double2x4([Double(deltaX), deltaXFixedPt, deltaXPt, ioHidScrollX],
                  [Double(deltaY), deltaYFixedPt, deltaYPt, ioHidScrollY])
    }

    func transform(matrix: double2x2) {
        let oldValue = matrixValue
        let newValue = oldValue * matrix
        // In case that Int(deltaX), Int(deltaY) = 0 when 0 < abs(deltaX), abs(deltaY) < 0.5.
        let deltaXY = newValue.transpose[0]
        let normalizedDeltaXY = sign(deltaXY) * max(_simd_round_d2(abs(deltaXY)), [1, 1])
        (deltaX, deltaXFixedPt, deltaXPt, ioHidScrollX) = (
            Int64(normalizedDeltaXY.x),
            newValue[0][1],
            newValue[0][2],
            newValue[0][3]
        )
        (deltaY, deltaYFixedPt, deltaYPt, ioHidScrollY) = (
            Int64(normalizedDeltaXY.y),
            newValue[1][1],
            newValue[1][2],
            newValue[1][3]
        )
        os_log("transform: oldValue=%{public}@, matrix=%{public}@, newValue=%{public}@", log: Self.log, type: .info,
               String(describing: oldValue),
               String(describing: matrix),
               String(describing: newValue))
    }

    func swapXY() {
        transform(matrix: .init([0, 1], [1, 0]))
    }

    func negate(vertically: Bool = false, horizontally: Bool = false) {
        transform(matrix: .init([horizontally ? -1 : 1, 0], [0, vertically ? -1 : 1]))
    }

    func scale(factor: Double) {
        scale(factorX: factor, factorY: factor)
    }

    func scale(factorX: Double = 1, factorY: Double = 1) {
        transform(matrix: .init([factorX, 0], [0, factorY]))
    }
}
