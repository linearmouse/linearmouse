//
//  ReverseScroll.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class ReverseScrolling: EventTransformer {
    private let vertically: Bool
    private let horizontally: Bool

    init(vertically: Bool = false, horizontally: Bool = false) {
        self.vertically = vertically
        self.horizontally = horizontally
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)
        if vertically {
            view.negateVertically()
        }
        if horizontally {
            view.negateHorizontally()
        }
        return event
    }
}
