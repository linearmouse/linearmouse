//
//  OrientNormalizer.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

/**
 This transformer normalize the orient of mouse wheel.

 Specifically, before macOS Big Sur (10.16), holding Shift while scrolling will swap
 `scrollWheelEventDeltaAxis2` (deltaX) and `scrollWheelEventDeltaAxis1` (deltaY)
 However, after macOS Big Sur, those values won't be swapped in that case.
 This transformer is to normalize the behavior to Big Sur's.

 This transformer has 2 phases:
 1. Check if the event should be normalized by swapping deltaX and deltaY. (Usually before all other transformers.)
 2. Restore deltaX and deltaY if they were swapped in the first phase. (Usually after all other transformers.)
 */
class OrientNormalizer: EventTransformer {
    private let _enabled: Bool?

    private enum Phase { case first, second }
    private var phase: Phase = .first

    private var enabled: Bool {
        if let value = _enabled {
            return value
        }
        if #available(macOS 10.16, *) {
            return true
        } else {
            return false
        }
    }

    private var hasSwapped = false

    init(enabled: Bool? = nil) {
        self._enabled = enabled
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        if !enabled {
            return event
        }

        let view = ScrollWheelEventView(event)
        switch phase {
        case .first:
            if view.deltaY == 0 {
                view.swapDeltaXY()
                hasSwapped = true
            }
            phase = .second
        case .second:
            if hasSwapped {
                view.swapDeltaXY()
            }
        }

        return event
    }
}
