//
//  ReverseScroll.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class ReverseScrolling: EventTransformer {
    private let mouseDetector: MouseDetector

    init(mouseDetector: MouseDetector) {
        self.mouseDetector = mouseDetector
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        guard mouseDetector.isMouseEvent(event) else {
            return event
        }

        let view = ScrollWheelEventView(event)
        view.deltaX = -view.deltaX
        view.deltaY = -view.deltaY
        return event
    }
}
