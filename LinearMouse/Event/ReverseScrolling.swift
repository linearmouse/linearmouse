//
//  ReverseScroll.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class ReverseScrolling: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)
        view.negate()
        return event
    }
}
