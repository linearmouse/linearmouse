// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension Scheme.Buttons.Mapping {
    enum Action: Equatable, Hashable {
        case simpleAction(SimpleAction)

        case run(String)

        case mouseWheelScrollUp(Scheme.Scrolling.Distance)
        case mouseWheelScrollDown(Scheme.Scrolling.Distance)
        case mouseWheelScrollLeft(Scheme.Scrolling.Distance)
        case mouseWheelScrollRight(Scheme.Scrolling.Distance)
    }
}

extension Scheme.Buttons.Mapping.Action: CustomStringConvertible {
    var description: String {
        switch self {
        case .simpleAction(.auto):
            return NSLocalizedString("Default action", comment: "")
        case .simpleAction(.none):
            return NSLocalizedString("No action", comment: "")
        case .simpleAction(.missionControl):
            return NSLocalizedString("Mission Control", comment: "")
        case .simpleAction(.spaceLeftDeprecated), .simpleAction(.missionControlSpaceLeft):
            return NSLocalizedString("Move left a space", comment: "")
        case .simpleAction(.spaceRightDeprecated), .simpleAction(.missionControlSpaceRight):
            return NSLocalizedString("Move right a space", comment: "")
        case .simpleAction(.appExpose):
            return NSLocalizedString("App Exposé", comment: "")
        case .simpleAction(.launchpad):
            return NSLocalizedString("Launchpad", comment: "")
        case .simpleAction(.showDesktop):
            return NSLocalizedString("Show desktop", comment: "")
        case .simpleAction(.displayBrightnessUp):
            return NSLocalizedString("Increase display brightness", comment: "")
        case .simpleAction(.displayBrightnessDown):
            return NSLocalizedString("Decrease display brightness", comment: "")
        case .simpleAction(.mediaVolumeUp):
            return NSLocalizedString("Increase volume", comment: "")
        case .simpleAction(.mediaVolumeDown):
            return NSLocalizedString("Decrease volume", comment: "")
        case .simpleAction(.mediaMute):
            return NSLocalizedString("Mute / unmute", comment: "")
        case .simpleAction(.mediaPlayPause):
            return NSLocalizedString("Play / pause", comment: "")
        case .simpleAction(.mediaNext):
            return NSLocalizedString("Next", comment: "")
        case .simpleAction(.mediaPrevious):
            return NSLocalizedString("Previous", comment: "")
        case .simpleAction(.mediaFastForward):
            return NSLocalizedString("Fast forward", comment: "")
        case .simpleAction(.mediaRewind):
            return NSLocalizedString("Rewind", comment: "")
        case .simpleAction(.keyboardBrightnessUp):
            return NSLocalizedString("Increase keyboard brightness", comment: "")
        case .simpleAction(.keyboardBrightnessDown):
            return NSLocalizedString("Decrease keyboard brightness", comment: "")
        case .simpleAction(.mouseWheelScrollUp):
            return NSLocalizedString("Scroll up", comment: "")
        case .simpleAction(.mouseWheelScrollDown):
            return NSLocalizedString("Scroll down", comment: "")
        case .simpleAction(.mouseWheelScrollLeft):
            return NSLocalizedString("Scroll left", comment: "")
        case .simpleAction(.mouseWheelScrollRight):
            return NSLocalizedString("Scroll right", comment: "")
        case .simpleAction(.mouseButtonLeft):
            return NSLocalizedString("Left click", comment: "")
        case .simpleAction(.mouseButtonMiddle):
            return NSLocalizedString("Middle click", comment: "")
        case .simpleAction(.mouseButtonRight):
            return NSLocalizedString("Right click", comment: "")
        case .simpleAction(.mouseButtonBack):
            return NSLocalizedString("Back", comment: "")
        case .simpleAction(.mouseButtonForward):
            return NSLocalizedString("Forward", comment: "")
        case let .run(command):
            return String(format: NSLocalizedString("Run: %@", comment: ""), command)
        case let .mouseWheelScrollUp(distance):
            return String(format: NSLocalizedString("Scroll up %@", comment: ""), String(describing: distance))
        case let .mouseWheelScrollDown(distance):
            return String(format: NSLocalizedString("Scroll down %@", comment: ""), String(describing: distance))
        case let .mouseWheelScrollLeft(distance):
            return String(format: NSLocalizedString("Scroll left %@", comment: ""), String(describing: distance))
        case let .mouseWheelScrollRight(distance):
            return String(format: NSLocalizedString("Scroll right %@", comment: ""), String(describing: distance))
        }
    }
}

extension Scheme.Buttons.Mapping.Action: Codable {
    enum SimpleAction: String, Codable, CaseIterable {
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
