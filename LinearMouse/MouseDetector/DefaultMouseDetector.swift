//
//  DefaultMouseDetector.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class DefaultMouseDetector: MouseDetector {
    func isMouseEvent(_ event: CGEvent) -> Bool {
        DeviceManager.shared.lastActiveDevice?.category == .mouse
    }
}
