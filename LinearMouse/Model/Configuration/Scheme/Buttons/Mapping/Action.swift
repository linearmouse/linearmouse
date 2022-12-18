// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

extension Scheme.Buttons.Mapping {
    enum Action {
        case simpleAction(SimpleAction)
        case run(String)
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

        case scrollUp = "scroll.up"
        case scrollDown = "scroll.down"
        case scrollLeft = "scroll.left"
        case scrollRight = "scroll.right"
    }

    enum ValueError: Error {
        case invalidValue
    }

    enum CodingKeys: String, CodingKey {
        case run
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let simpleAction = try? container.decode(SimpleAction.self) {
            self = .simpleAction(simpleAction)
            return
        }

        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let command = try? container.decode(String.self, forKey: .run) {
            self = .run(command)
            return
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
