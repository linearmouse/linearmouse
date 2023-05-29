// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation

extension Scheme.Buttons.Mapping.Action: Codable {
    enum SimpleAction: String, Codable, Identifiable, CaseIterable {
        var id: Self { self }

        case auto
        case none

        case spaceLeftDeprecated = "spaceLeft"
        case spaceRightDeprecated = "spaceRight"

        case missionControl
        case missionControlSpaceLeft = "missionControl.spaceLeft"
        case missionControlSpaceRight = "missionControl.spaceRight"

        case appExpose
        case launchpad
        case showDesktop
        case lookUpAndDataDetectors
        case smartZoom

        case displayBrightnessUp = "display.brightnessUp"
        case displayBrightnessDown = "display.brightnessDown"

        case mediaVolumeUp = "media.volumeUp"
        case mediaVolumeDown = "media.volumeDown"
        case mediaMute = "media.mute"
        case mediaPlayPause = "media.playPause"
        case mediaNext = "media.next"
        case mediaPrevious = "media.previous"
        case mediaFastForward = "media.fastForward"
        case mediaRewind = "media.rewind"

        case keyboardBrightnessUp = "keyboard.brightnessUp"
        case keyboardBrightnessDown = "keyboard.brightnessDown"

        case mouseWheelScrollUp = "mouse.wheel.scrollUp"
        case mouseWheelScrollDown = "mouse.wheel.scrollDown"
        case mouseWheelScrollLeft = "mouse.wheel.scrollLeft"
        case mouseWheelScrollRight = "mouse.wheel.scrollRight"

        case mouseButtonLeft = "mouse.button.left"
        case mouseButtonMiddle = "mouse.button.middle"
        case mouseButtonRight = "mouse.button.right"
        case mouseButtonBack = "mouse.button.back"
        case mouseButtonForward = "mouse.button.forward"
    }

    enum ValueError: Error {
        case invalidValue
    }

    enum CodingKeys: String, CodingKey {
        case run

        case mouseWheelScrollUp = "mouse.wheel.scrollUp"
        case mouseWheelScrollDown = "mouse.wheel.scrollDown"
        case mouseWheelScrollLeft = "mouse.wheel.scrollLeft"
        case mouseWheelScrollRight = "mouse.wheel.scrollRight"
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let simpleAction = try? container.decode(SimpleAction.self) {
            self = .simpleAction(simpleAction)
            return
        }

        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let command = try? container.decode(String.self, forKey: .run) {
                self = .run(command)
                return
            }

            if let distance = try? container.decode(Scheme.Scrolling.Distance.self, forKey: .mouseWheelScrollUp) {
                self = .mouseWheelScrollUp(distance)
                return
            }

            if let distance = try? container.decode(Scheme.Scrolling.Distance.self, forKey: .mouseWheelScrollDown) {
                self = .mouseWheelScrollDown(distance)
                return
            }

            if let distance = try? container.decode(Scheme.Scrolling.Distance.self, forKey: .mouseWheelScrollLeft) {
                self = .mouseWheelScrollLeft(distance)
                return
            }

            if let distance = try? container.decode(Scheme.Scrolling.Distance.self, forKey: .mouseWheelScrollRight) {
                self = .mouseWheelScrollRight(distance)
                return
            }
        }

        throw CustomDecodingError(codingPath: decoder.codingPath, error: ValueError.invalidValue)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .simpleAction(simpleAction):
            var container = encoder.singleValueContainer()
            try container.encode(simpleAction)

        case let .run(command):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(command, forKey: .run)

        case let .mouseWheelScrollUp(distance):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(distance, forKey: .mouseWheelScrollUp)

        case let .mouseWheelScrollDown(distance):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(distance, forKey: .mouseWheelScrollDown)

        case let .mouseWheelScrollLeft(distance):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(distance, forKey: .mouseWheelScrollLeft)

        case let .mouseWheelScrollRight(distance):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(distance, forKey: .mouseWheelScrollRight)
        }
    }
}

extension Scheme.Buttons.Mapping.Action.ValueError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidValue:
            let simpleActions = Scheme.Buttons.Mapping.Action.SimpleAction.allCases
                .map { "\"\($0)\"" }
                .joined(separator: ", ")
            return NSLocalizedString("Action must be \(simpleActions) or { \"run\": \"<command>\" }", comment: "")
        }
    }
}
