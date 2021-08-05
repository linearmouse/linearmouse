//
//  SideButtonFixer.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/8/5.
//

import Foundation

func fixSideButtonsEvent(_ event: CGEvent) -> CGEvent? {
    let defaults = AppDefaults.shared
    guard defaults.universalBackForwardOn else {
        return event
    }

    guard event.type == .otherMouseUp else {
        return event
    }

    switch event.getIntegerValueField(.mouseEventButtonNumber) {
    case 3: // back
        simulateSwipeLeft()
        return nil
    case 4: // forward
        simulateSwipeRight()
        return nil
    default:
        return event
    }
}
