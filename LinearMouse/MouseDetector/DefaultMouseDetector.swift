//
//  DefaultMouseDetector.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class DefaultMouseDetector: MouseDetector {
    func isMouseEvent(_ event: CGEvent) -> Bool {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        return !continuous
    }
}
