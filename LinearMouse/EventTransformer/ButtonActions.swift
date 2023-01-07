// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import AppKit
import DockKit
import Foundation
import KeyKit
import os.log

class ButtonActions {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ButtonActions")

    let mappings: [Scheme.Buttons.Mapping]

    var timer: Timer?

    init(mappings: [Scheme.Buttons.Mapping]) {
        self.mappings = mappings
    }

    deinit {
        timer?.invalidate()
    }
}

extension ButtonActions: EventTransformer {
    var mouseDownEventTypes: [CGEventType] {
        [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    }

    var mouseUpEventTypes: [CGEventType] {
        [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard mouseDownEventTypes.contains(event.type) || mouseUpEventTypes.contains(event.type) else {
            return event
        }

        timer?.invalidate()

        guard let action = matchAction(of: event) else {
            return event
        }

        guard mouseDownEventTypes.contains(event.type) else {
            return nil
        }

        DispatchQueue.main.async { [self] in
            executeIgnoreErrors(action: action)

            // FIXME: `NSEvent.keyRepeatDelay` and `NSEvent.keyRepeatInterval` are not kept up to date

            guard NSEvent.keyRepeatDelay > 0, NSEvent.keyRepeatInterval > 0 else {
                return
            }

            timer = Timer.scheduledTimer(
                withTimeInterval: NSEvent.keyRepeatDelay,
                repeats: false,
                block: { [weak self] _ in
                    guard let self = self else {
                        return
                    }

                    self.executeIgnoreErrors(action: action)

                    self.timer = Timer.scheduledTimer(
                        withTimeInterval: NSEvent.keyRepeatInterval,
                        repeats: true,
                        block: { [weak self] _ in
                            guard let self = self else {
                                return
                            }

                            self.executeIgnoreErrors(action: action)
                        }
                    )
                }
            )
        }

        return nil
    }

    private func matchAction(of event: CGEvent) -> Scheme.Buttons.Mapping.Action? {
        guard let mapping = mappings.last(where: { $0.match(with: event) }),
              let action = mapping.action else {
            return nil
        }

        if case .simpleAction(.auto) = action {
            return nil
        }

        return action
    }

    private func executeIgnoreErrors(action: Scheme.Buttons.Mapping.Action) {
        do {
            os_log("Execute action: %{public}@", log: Self.log, type: .debug,
                   String(describing: action))

            try execute(action: action)
        } catch {
            os_log("Failed to execute: %{public}@: %{public}@", log: Self.log, type: .error,
                   String(describing: action),
                   String(describing: error))
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func execute(action: Scheme.Buttons.Mapping.Action) throws {
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

        case .simpleAction(.mouseWheelScrollUp):
            postScrollEvent(horizontal: 0, vertical: 3)

        case .simpleAction(.mouseWheelScrollDown):
            postScrollEvent(horizontal: 0, vertical: -3)

        case .simpleAction(.mouseWheelScrollLeft):
            postScrollEvent(horizontal: 3, vertical: 0)

        case .simpleAction(.mouseWheelScrollRight):
            postScrollEvent(horizontal: -3, vertical: 0)

        case let .run(command):
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            task.launch()

        case let .mouseWheelScrollUp(distance):
            postScrollEvent(direction: .up, distance: distance)

        case let .mouseWheelScrollDown(distance):
            postScrollEvent(direction: .down, distance: distance)

        case let .mouseWheelScrollLeft(distance):
            postScrollEvent(direction: .left, distance: distance)

        case let .mouseWheelScrollRight(distance):
            postScrollEvent(direction: .right, distance: distance)
        }
    }

    private func postScrollEvent(horizontal: Int32, vertical: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                  wheel1: vertical, wheel2: horizontal, wheel3: 0) else {
            return
        }

        event.flags = []
        event.post(tap: .cgSessionEventTap)
    }

    private func postContinuousScrollEvent(horizontal: Double, vertical: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: 0, wheel2: 0, wheel3: 0) else {
            return
        }

        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontal)

        event.flags = []
        event.post(tap: .cgSessionEventTap)
    }

    private enum ScrollEventDirection {
        case up, down, left, right
    }

    private func postScrollEvent(direction: ScrollEventDirection,
                                 distance: Scheme.Scrolling.Distance) {
        switch distance {
        case .auto:
            switch direction {
            case .up:
                postScrollEvent(horizontal: 0, vertical: 3)
            case .down:
                postScrollEvent(horizontal: 0, vertical: -3)
            case .left:
                postScrollEvent(horizontal: 3, vertical: 0)
            case .right:
                postScrollEvent(horizontal: -3, vertical: 0)
            }

        case let .line(value):
            let value = Int32(value)

            switch direction {
            case .up:
                postScrollEvent(horizontal: 0, vertical: value)
            case .down:
                postScrollEvent(horizontal: 0, vertical: -value)
            case .left:
                postScrollEvent(horizontal: value, vertical: 0)
            case .right:
                postScrollEvent(horizontal: -value, vertical: 0)
            }

        case let .pixel(value):
            let value = value.asTruncatedDouble

            switch direction {
            case .up:
                postContinuousScrollEvent(horizontal: 0, vertical: value)
            case .down:
                postContinuousScrollEvent(horizontal: 0, vertical: -value)
            case .left:
                postContinuousScrollEvent(horizontal: value, vertical: 0)
            case .right:
                postContinuousScrollEvent(horizontal: -value, vertical: 0)
            }
        }
    }
}
