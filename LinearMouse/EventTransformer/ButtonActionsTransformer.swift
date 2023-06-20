// MIT License
// Copyright (c) 2021-2023 LinearMouse

import AppKit
import DockKit
import Foundation
import GestureKit
import KeyKit
import os.log

class ButtonActionsTransformer {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ButtonActions")

    let mappings: [Scheme.Buttons.Mapping]

    var repeatTimer: Timer?

    let keySimulator = KeySimulator()

    init(mappings: [Scheme.Buttons.Mapping]) {
        self.mappings = mappings
    }

    deinit {
        repeatTimer?.invalidate()
    }
}

extension ButtonActionsTransformer: EventTransformer {
    var mouseDownEventTypes: [CGEventType] {
        [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    }

    var mouseUpEventTypes: [CGEventType] {
        [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    }

    var mouseDraggedEventTypes: [CGEventType] {
        [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    }

    var scrollWheelsEventTypes: [CGEventType] {
        [.scrollWheel]
    }

    var keyTypes: [CGEventType] {
        [.keyDown, .keyUp]
    }

    var allEventTypesOfInterest: [CGEventType] {
        [mouseDownEventTypes, mouseUpEventTypes, mouseDraggedEventTypes, scrollWheelsEventTypes, keyTypes]
            .flatMap { $0 }
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard allEventTypesOfInterest.contains(event.type) else {
            return event
        }

        guard !SettingsState.shared.recording else {
            return event
        }

        if keyTypes.contains(event.type), let flags = keySimulator.updateCGEventFlags(event) {
            os_log("CGEvent flags updated to %{public}@", log: Self.log, type: .info,
                   String(describing: flags))
        }

        repeatTimer?.invalidate()
        repeatTimer = nil

        guard let mapping = findMapping(of: event) else {
            return event
        }

        guard let action = mapping.action else {
            return event
        }

        if case .arg0(.auto) = action {
            return event
        }

        if event.type == .scrollWheel {
            queueActions(event: event.copy(), action: action)
        } else {
            // FIXME: `NSEvent.keyRepeatDelay` and `NSEvent.keyRepeatInterval` are not kept up to date
            // TODO: Support override `repeatDelay` and `repeatInterval`
            let keyRepeatDelay = mapping.repeat == true ? NSEvent.keyRepeatDelay : 0
            let keyRepeatInterval = mapping.repeat == true ? NSEvent.keyRepeatInterval : 0
            let keyRepeatEnabled = keyRepeatDelay > 0 && keyRepeatInterval > 0

            if !keyRepeatEnabled {
                if handleButtonSwaps(event: event, action: action) {
                    return event
                }
                if handleKeyPress(event: event, action: action) {
                    return nil
                }
            }

            // Actions are executed when button is down if key repeat is enabled; otherwise, actions are
            // executed when button is up.
            let eventsOfInterest = keyRepeatEnabled ? mouseDownEventTypes : mouseUpEventTypes

            guard eventsOfInterest.contains(event.type) else {
                return nil
            }

            queueActions(event: event.copy(),
                         action: action,
                         keyRepeatEnabled: keyRepeatEnabled,
                         keyRepeatDelay: keyRepeatDelay,
                         keyRepeatInterval: keyRepeatInterval)
        }

        return nil
    }

    private func findMapping(of event: CGEvent) -> Scheme.Buttons.Mapping? {
        mappings.last { $0.match(with: event) }
    }

    private func queueActions(event _: CGEvent?,
                              action: Scheme.Buttons.Mapping.Action,
                              keyRepeatEnabled: Bool = false,
                              keyRepeatDelay: TimeInterval = 0,
                              keyRepeatInterval: TimeInterval = 0) {
        DispatchQueue.main.async { [self] in
            executeIgnoreErrors(action: action)

            guard keyRepeatEnabled else {
                return
            }

            repeatTimer = Timer.scheduledTimer(
                withTimeInterval: keyRepeatDelay,
                repeats: false,
                block: { [weak self] _ in
                    guard let self = self else {
                        return
                    }

                    self.executeIgnoreErrors(action: action)

                    self.repeatTimer = Timer.scheduledTimer(
                        withTimeInterval: keyRepeatInterval,
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
    }

    private func executeIgnoreErrors(action: Scheme.Buttons.Mapping.Action) {
        do {
            os_log("Execute action: %{public}@", log: Self.log, type: .info,
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
        case .arg0(.none), .arg0(.auto):
            return

        case .arg0(.missionControlSpaceLeft):
            try postSymbolicHotKey(.spaceLeft)

        case .arg0(.missionControlSpaceRight):
            try postSymbolicHotKey(.spaceRight)

        case .arg0(.missionControl):
            missionControl()

        case .arg0(.appExpose):
            appExpose()

        case .arg0(.launchpad):
            launchpad()

        case .arg0(.showDesktop):
            showDesktop()

        case .arg0(.lookUpAndDataDetectors):
            try postSymbolicHotKey(.lookUpWordInDictionary)

        case .arg0(.smartZoom):
            GestureEvent(zoomToggleSource: nil)?.post(tap: .cgSessionEventTap)

        case .arg0(.displayBrightnessUp):
            postSystemDefinedKey(.brightnessUp)

        case .arg0(.displayBrightnessDown):
            postSystemDefinedKey(.brightnessDown)

        case .arg0(.mediaVolumeUp):
            postSystemDefinedKey(.soundUp)

        case .arg0(.mediaVolumeDown):
            postSystemDefinedKey(.soundDown)

        case .arg0(.mediaMute):
            postSystemDefinedKey(.mute)

        case .arg0(.mediaPlayPause):
            postSystemDefinedKey(.play)

        case .arg0(.mediaNext):
            postSystemDefinedKey(.next)

        case .arg0(.mediaPrevious):
            postSystemDefinedKey(.previous)

        case .arg0(.mediaFastForward):
            postSystemDefinedKey(.fast)

        case .arg0(.mediaRewind):
            postSystemDefinedKey(.rewind)

        case .arg0(.keyboardBrightnessUp):
            postSystemDefinedKey(.illuminationUp)

        case .arg0(.keyboardBrightnessDown):
            postSystemDefinedKey(.illuminationDown)

        case .arg0(.mouseWheelScrollUp):
            postScrollEvent(horizontal: 0, vertical: 3)

        case .arg0(.mouseWheelScrollDown):
            postScrollEvent(horizontal: 0, vertical: -3)

        case .arg0(.mouseWheelScrollLeft):
            postScrollEvent(horizontal: 3, vertical: 0)

        case .arg0(.mouseWheelScrollRight):
            postScrollEvent(horizontal: -3, vertical: 0)

        case .arg0(.mouseButtonLeft):
            postClickEvent(mouseButton: .left)

        case .arg0(.mouseButtonMiddle):
            postClickEvent(mouseButton: .center)

        case .arg0(.mouseButtonRight):
            postClickEvent(mouseButton: .right)

        case .arg0(.mouseButtonBack):
            postClickEvent(mouseButton: .back)

        case .arg0(.mouseButtonForward):
            postClickEvent(mouseButton: .forward)

        case let .arg1(.run(command)):
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            task.launch()

        case let .arg1(.mouseWheelScrollUp(distance)):
            postScrollEvent(direction: .up, distance: distance)

        case let .arg1(.mouseWheelScrollDown(distance)):
            postScrollEvent(direction: .down, distance: distance)

        case let .arg1(.mouseWheelScrollLeft(distance)):
            postScrollEvent(direction: .left, distance: distance)

        case let .arg1(.mouseWheelScrollRight(distance)):
            postScrollEvent(direction: .right, distance: distance)

        case let .arg1(.keyPress(keys)):
            try keySimulator.press(keys: keys)
            keySimulator.reset()
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

    private func handleButtonSwaps(event: CGEvent, action: Scheme.Buttons.Mapping.Action) -> Bool {
        guard [mouseDownEventTypes, mouseUpEventTypes, mouseDraggedEventTypes]
            .flatMap({ $0 }).contains(event.type)
        else {
            return false
        }

        let mouseEventView = MouseEventView(event)

        switch action {
        case .arg0(.mouseButtonLeft):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .left
        case .arg0(.mouseButtonMiddle):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .center
        case .arg0(.mouseButtonRight):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .right
        case .arg0(.mouseButtonBack):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .back
        case .arg0(.mouseButtonForward):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .forward
        default:
            return false
        }

        os_log("Set mouse button to %{public}@", log: Self.log, type: .info,
               String(describing: mouseEventView.mouseButtonDescription))

        return true
    }

    private func handleKeyPress(event: CGEvent, action: Scheme.Buttons.Mapping.Action) -> Bool {
        guard [mouseDownEventTypes, mouseUpEventTypes, mouseDraggedEventTypes]
            .flatMap({ $0 }).contains(event.type)
        else {
            return false
        }

        switch action {
        case let .arg1(.keyPress(keys)) where mouseDownEventTypes.contains(event.type):
            os_log("Down keys: %{public}@", log: Self.log, type: .info,
                   String(describing: keys))
            try? keySimulator.down(keys: keys)
            return true
        case let .arg1(.keyPress(keys)) where mouseUpEventTypes.contains(event.type):
            os_log("Up keys: %{public}@", log: Self.log, type: .info,
                   String(describing: keys))
            try? keySimulator.up(keys: keys)
            keySimulator.reset()
            return true
        default:
            return false
        }
    }

    private func postClickEvent(mouseButton: CGMouseButton) {
        guard let location = CGEvent(source: nil)?.location else {
            return
        }

        guard let mouseDownEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: .leftMouseDown),
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) else {
            return
        }
        guard let mouseUpEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: .leftMouseUp),
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) else {
            return
        }

        mouseDownEvent.post(tap: .cgSessionEventTap)
        mouseUpEvent.post(tap: .cgSessionEventTap)
    }
}

extension ButtonActionsTransformer: Deactivatable {
    func deactivate() {
        if let repeatTimer = repeatTimer {
            os_log("ButtonActionsTransformer is inactive, invalidate the repeat timer", log: Self.log, type: .info)
            repeatTimer.invalidate()
            self.repeatTimer = nil
        }
    }
}
