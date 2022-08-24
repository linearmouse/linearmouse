// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import AppKit
import DockKit
import Foundation
import KeyKit
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
        guard let mapping = mappings.last(where: { event.match(with: $0) }),
              let action = mapping.action else {
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

        let view = MouseEventView(event)

        guard let action = action(of: event) else {
            os_log("No button mapping found: button=%{public}@", log: Self.log, type: .debug,
                   view.mouseButtonDescription)
            return event
        }

        os_log("Found mapping: button=%{public}@, mapping=%{public}@", log: Self.log, type: .debug,
               view.mouseButtonDescription, String(describing: action))

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

        case .simpleAction(.missionControlSpaceLeft),
             .simpleAction(.spaceLeftDeprecated):
            try postSymbolicHotKey(.spaceLeft)

        case .simpleAction(.missionControlSpaceRight),
             .simpleAction(.spaceRightDeprecated):
            try postSymbolicHotKey(.spaceRight)

        case .simpleAction(.missionControl):
            missionControl()

        case .simpleAction(.appExpose):
            appExpose()

        case .simpleAction(.launchpad):
            launchpad()

        case .simpleAction(.showDesktop):
            showDesktop()

        case .simpleAction(.displayBrightnessUp):
            postSystemDefinedKey(.brightnessUp)

        case .simpleAction(.displayBrightnessDown):
            postSystemDefinedKey(.brightnessDown)

        case .simpleAction(.mediaVolumeUp):
            postSystemDefinedKey(.soundUp)

        case .simpleAction(.mediaVolumeDown):
            postSystemDefinedKey(.soundDown)

        case .simpleAction(.mediaMute):
            postSystemDefinedKey(.mute)

        case .simpleAction(.mediaPlayPause):
            postSystemDefinedKey(.play)

        case .simpleAction(.mediaNext):
            postSystemDefinedKey(.next)

        case .simpleAction(.mediaPrevious):
            postSystemDefinedKey(.previous)

        case .simpleAction(.mediaFastForward):
            postSystemDefinedKey(.fast)

        case .simpleAction(.mediaRewind):
            postSystemDefinedKey(.rewind)

        case .simpleAction(.keyboardBrightnessUp):
            postSystemDefinedKey(.illuminationUp)

        case .simpleAction(.keyboardBrightnessDown):
            postSystemDefinedKey(.illuminationDown)

        case let .run(command):
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            task.launch()
        }
    }
}

extension CGEventFlags {
    func match(with mapping: Scheme.Buttons.Mapping) -> Bool {
        guard mapping.command ?? false == contains(.maskCommand),
              mapping.shift ?? false == contains(.maskShift),
              mapping.option ?? false == contains(.maskAlternate),
              mapping.control ?? false == contains(.maskControl) else {
            return false
        }

        return true
    }
}

extension CGEvent {
    func match(with mapping: Scheme.Buttons.Mapping) -> Bool {
        let button = getIntegerValueField(.mouseEventButtonNumber)

        guard mapping.button == button,
              flags.match(with: mapping) else {
            return false
        }

        return true
    }
}
