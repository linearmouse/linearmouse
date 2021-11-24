//
//  MouseDetector.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

protocol MouseDetector {
    func isMouseEvent(_ event: CGEvent) -> Bool
}
