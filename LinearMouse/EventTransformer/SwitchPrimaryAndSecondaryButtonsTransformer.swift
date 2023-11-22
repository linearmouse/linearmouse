// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation
import os.log

enum SwitchPrimaryAndSecondaryButtonsTransformer {
    static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "SwitchPrimaryAndSecondaryButtonsTransformer"
    )
}

extension SwitchPrimaryAndSecondaryButtonsTransformer: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        let mouseEventView = MouseEventView(event)

        guard var mouseButton = mouseEventView.mouseButton else {
            return event
        }

        switch mouseButton {
        case .left:
            mouseButton = .right
        case .right:
            mouseButton = .left
        default:
            return event
        }

        mouseEventView.mouseButton = mouseButton
        event.type = mouseButton.fixedCGEventType(of: event.type)
        os_log("Switched primary and secondary button: %{public}s",
               log: Self.log, type: .info,
               String(describing: mouseButton))

        return event
    }
}
