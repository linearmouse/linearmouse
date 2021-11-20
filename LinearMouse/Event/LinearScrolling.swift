//
//  LinearScrolling.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class LinearScrolling: EventTransformer {
    private let appDefaults: AppDefaults
    private let mouseDetector: MouseDetector

    init(appDefaults: AppDefaults, mouseDetector: MouseDetector) {
        self.appDefaults = appDefaults
        self.mouseDetector = mouseDetector
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        guard appDefaults.linearScrollingOn else {
            return event
        }

        guard mouseDetector.isMouseEvent(event) else {
            return event
        }

        let view = ScrollWheelEventView(event)
        let scrollLines = Int64(appDefaults.scrollLines)
        view.deltaX = view.deltaX.signum() * scrollLines
        view.deltaY = view.deltaY.signum() * scrollLines
        return event
    }
}
