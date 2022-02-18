//
//  LinearScrolling.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

class LinearScrolling: EventTransformer {
    private let scrollLines: Int

    init(scrollLines: Int) {
        self.scrollLines = scrollLines
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)
        guard view.momentumPhase == .none else {
            return nil
        }
        view.deltaX = view.deltaX.signum() * Int64(scrollLines)
        view.deltaY = view.deltaY.signum() * Int64(scrollLines)
        return event
    }
}
