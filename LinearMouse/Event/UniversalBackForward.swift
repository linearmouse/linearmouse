//
//  SideButtonFixer.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/8/5.
//

import Foundation

extension CGMouseButton {
    static let back = CGMouseButton(rawValue: 3)!
    static let forward = CGMouseButton(rawValue: 4)!
}

class UniversalBackForward: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .otherMouseDown || event.type == .otherMouseUp else {
            return event
        }

        let view = MouseEventView(event)
        guard let mouseButton = view.mouseButton else {
            return event
        }
        let shouldFire = event.type == .otherMouseDown
        switch mouseButton {
        case .back:
            if shouldFire {
                simulateSwipeLeft()
            }
        case .forward:
            if shouldFire {
                simulateSwipeRight()
            }
        default:
            return event
        }
        return nil
    }
}
