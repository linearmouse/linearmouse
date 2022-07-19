// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

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

        if case .auto = action {
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
            exec(action: action)
        }

        return nil
    }

    func exec(action: Scheme.Buttons.Mapping.Action) {
        switch action {
        case .none, .auto:
            return

        case let .run(command):
            DispatchQueue.main.async {
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = ["-c", command]
                task.launch()
            }
        }
    }
}
