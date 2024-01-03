// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation

class ReverseScrollingTransformer: EventTransformer {
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
        view.negate(vertically: vertically, horizontally: horizontally)
        return event
    }
}
