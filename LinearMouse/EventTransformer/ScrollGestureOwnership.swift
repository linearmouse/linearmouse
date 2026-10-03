// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// One physical event is either consumed or forwarded as a whole. Retain the
/// latest direct sample's handling through its momentum tail, across routes.
final class ScrollGestureOwnership {
    private enum Consumption {
        case discard
        case scroll((ScrollWheelEventView) -> Void)
    }

    private var consumption: Consumption?

    var isOwned: Bool {
        consumption != nil
    }

    func claim() {
        consumption = .discard
    }

    func retainScroll(consume: @escaping (ScrollWheelEventView) -> Void) {
        consumption = .scroll(consume)
    }

    /// Return true when the physical event is owned. Scroll tails emit mapped
    /// output; command tails are simply discarded. Neither leaks raw scrolling.
    func consumeMomentum(_ view: ScrollWheelEventView) -> Bool {
        guard let consumption else {
            return false
        }
        if case let .scroll(consume) = consumption {
            consume(view)
        }
        return true
    }

    func release() {
        consumption = nil
    }
}
