// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation
import KeyKit

extension Scheme.Buttons.Mapping.Action: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Arg0.self) {
            self = .arg0(value)
            return
        }

        if let value = try? container.decode(Arg1.self) {
            self = .arg1(value)
            return
        }

        self = .arg0(.auto)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .arg0(value):
            try container.encode(value)

        case let .arg1(value):
            try container.encode(value)
        }
    }
}

extension Scheme.Buttons.Mapping.Action.Arg1: Codable {
    enum CodingKeys: String, CodingKey {
        case run

        case mouseWheelScrollUp = "mouse.wheel.scrollUp"
        case mouseWheelScrollDown = "mouse.wheel.scrollDown"
        case mouseWheelScrollLeft = "mouse.wheel.scrollLeft"
        case mouseWheelScrollRight = "mouse.wheel.scrollRight"
        case keyPress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

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

        if let keys = try? container.decode([Key].self, forKey: .keyPress) {
            self = .keyPress(keys)
            return
        }

        throw CustomDecodingError(in: container, error: DecodingError.invalidValue)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
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

        case let .keyPress(keys):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keys, forKey: .keyPress)
        }
    }

    enum DecodingError: Error {
        case invalidValue
    }
}
