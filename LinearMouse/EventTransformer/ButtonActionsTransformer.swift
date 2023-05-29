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

    var allEventTypesOfInterest: [CGEventType] {
        [mouseDownEventTypes, mouseUpEventTypes, mouseDraggedEventTypes, scrollWheelsEventTypes]
            .flatMap { $0 }
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard allEventTypesOfInterest.contains(event.type) else {
            return event
        }

        guard !SettingsState.shared.recording else {
            return event
        }

        repeatTimer?.invalidate()

        guard let mapping = findMapping(of: event) else {
            return event
        }

        guard let action = mapping.action else {
            return event
        }

        if case .simpleAction(.auto) = action {
            return event
        }

        var eventsOfInterest: [CGEventType] = []
        if event.type == .scrollWheel {
            queueActions(action: action)
        } else {
            // FIXME: `NSEvent.keyRepeatDelay` and `NSEvent.keyRepeatInterval` are not kept up to date
            // TODO: Support override `repeatDelay` and `repeatInterval`
            let keyRepeatDelay = mapping.repeat == true ? NSEvent.keyRepeatDelay : 0
            let keyRepeatInterval = mapping.repeat == true ? NSEvent.keyRepeatInterval : 0
            let keyRepeatEnabled = keyRepeatDelay > 0 && keyRepeatInterval > 0

            if !keyRepeatEnabled, handleSimpleButtonMappings(event: event, action: action) {
                return event
            }

            // Actions are executed when button is down if key repeat is enabled; otherwise, actions are
            // executed when button is up.
            eventsOfInterest = keyRepeatEnabled ? mouseDownEventTypes : mouseUpEventTypes

            guard eventsOfInterest.contains(event.type) else {
                return nil
            }

            queueActions(action: action,
                         keyRepeatEnabled: keyRepeatEnabled,
                         keyRepeatDelay: keyRepeatDelay,
                         keyRepeatInterval: keyRepeatInterval)
        }

        return nil
    }

    private func findMapping(of event: CGEvent) -> Scheme.Buttons.Mapping? {
        mappings.last { $0.match(with: event) }
    }

    private func queueActions(action: Scheme.Buttons.Mapping.Action,
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
        case .simpleAction(.none), .simpleAction(.auto):
            return

        case .simpleAction(.missionControlSpaceLeft):
            try postSymbolicHotKey(.spaceLeft)

        case .simpleAction(.missionControlSpaceRight):
            try postSymbolicHotKey(.spaceRight)

        case .simpleAction(.missionControl):
            missionControl()

        case .simpleAction(.appExpose):
            appExpose()

        case .simpleAction(.launchpad):
            launchpad()

        case .simpleAction(.showDesktop):
            showDesktop()

        case .simpleAction(.lookUpAndDataDetectors):
            try postSymbolicHotKey(.lookUpWordInDictionary)

        case .simpleAction(.smartZoom):
            GestureEvent(zoomToggleSource: nil)?.post(tap: .cgSessionEventTap)

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

        case .simpleAction(.mouseButtonLeft):
            postClickEvent(mouseButton: .left)

        case .simpleAction(.mouseButtonMiddle):
            postClickEvent(mouseButton: .center)

        case .simpleAction(.mouseButtonRight):
            postClickEvent(mouseButton: .right)

        case .simpleAction(.mouseButtonBack):
            postClickEvent(mouseButton: .back)

        case .simpleAction(.mouseButtonForward):
            postClickEvent(mouseButton: .forward)

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

    private func handleSimpleButtonMappings(event: CGEvent, action: Scheme.Buttons.Mapping.Action) -> Bool {
        guard [mouseDownEventTypes, mouseUpEventTypes, mouseDraggedEventTypes].flatMap({ $0 }).contains(event.type)
        else {
            return false
        }

        let mouseEventView = MouseEventView(event)

        switch action {
        case .simpleAction(.mouseButtonLeft):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .left
        case .simpleAction(.mouseButtonMiddle):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .center
        case .simpleAction(.mouseButtonRight):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .right
        case .simpleAction(.mouseButtonBack):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .back
        case .simpleAction(.mouseButtonForward):
            mouseEventView.modifierFlags = []
            mouseEventView.mouseButton = .forward
        default:
            return false
        }

        return true
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
