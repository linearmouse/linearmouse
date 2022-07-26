// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import AppKit
import CGSKit
import DockKit
import Foundation
import os.log

class ButtonActions {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ButtonActions")

    let mappings: [Scheme.Buttons.Mapping]

    init(mappings: [Scheme.Buttons.Mapping]) {
        self.mappings = mappings
    }
}

extension ButtonActions: EventTransformer {
    var mouseDownEventTypes: [CGEventType] {
        [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    }

    var mouseUpEventTypes: [CGEventType] {
        [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    }

    func action(of event: CGEvent) -> Scheme.Buttons.Mapping.Action? {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        func match(with mapping: Scheme.Buttons.Mapping) -> Bool {
            guard mapping.button == button,
                  mapping.command ?? false == event.flags.contains(.maskCommand),
                  mapping.shift ?? false == event.flags.contains(.maskShift),
                  mapping.option ?? false == event.flags.contains(.maskAlternate),
                  mapping.control ?? false == event.flags.contains(.maskControl)
            else {
                return false
            }

            return true
        }

        guard let mapping = mappings.last(where: match),
              let action = mapping.action else {
            os_log("No button mapping found for button %{public}d", log: Self.log, type: .debug, button)

            return nil
        }

        if case .simpleAction(.auto) = action {
            return nil
        }

        return action
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard mouseDownEventTypes.contains(event.type) || mouseUpEventTypes.contains(event.type) else {
            return event
        }

        guard let action = action(of: event) else {
            return event
        }

        os_log("Find mapping: %{public}@", log: Self.log, type: .debug, String(describing: action))

        if mouseUpEventTypes.contains(event.type) {
            DispatchQueue.main.async { [self] in
                do {
                    try exec(action: action)
                } catch {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = String(describing: error)
                    alert.runModal()
                }
            }
        }

        return nil
    }

    func exec(action: Scheme.Buttons.Mapping.Action) throws {
        switch action {
        case .simpleAction(.none), .simpleAction(.auto):
            return

        case .simpleAction(.spaceLeft):
            try postSymbolicHotKey(.spaceLeft)

        case .simpleAction(.spaceRight):
            try postSymbolicHotKey(.spaceRight)

        case .simpleAction(.missionControl):
            missionControl()

        case .simpleAction(.appExpose):
            appExpose()

        case .simpleAction(.launchpad):
            launchpad()

        case .simpleAction(.showDesktop):
            showDesktop()

        case let .run(command):
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            task.launch()
        }
    }
}
