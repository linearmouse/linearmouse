//
//  LinearScrolling.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class LinearScrolling: EventTransformer {
    private let mouseDetector: MouseDetector
    private let scrollLines: Int

    init(mouseDetector: MouseDetector, scrollLines: Int) {
        self.mouseDetector = mouseDetector
        self.scrollLines = scrollLines
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        guard mouseDetector.isMouseEvent(event) else {
            return event
        }

        let view = ScrollWheelEventView(event)
        view.deltaX = view.deltaX.signum() * Int64(scrollLines)
        view.deltaY = view.deltaY.signum() * Int64(scrollLines)
        return event
    }
}
