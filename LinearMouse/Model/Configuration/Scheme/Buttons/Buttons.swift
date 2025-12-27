// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

extension Scheme {
    struct Buttons: Codable, Equatable, ImplicitInitable {
        var mappings: [Mapping]?

        enum UniversalBackForward {
            case none
            case both
            case backOnly
            case forwardOnly
        }

        var universalBackForward: UniversalBackForward?

        var switchPrimaryButtonAndSecondaryButtons: Bool?

        @ImplicitOptional var clickDebouncing: ClickDebouncing

        @ImplicitOptional var gesture: Gesture
    }
}

extension Scheme.Buttons {
    func merge(into buttons: inout Self) {
        if let mappings, !mappings.isEmpty {
            buttons.mappings = (buttons.mappings ?? []) + mappings
        }

        if let universalBackForward {
            buttons.universalBackForward = universalBackForward
        }

        if let switchPrimaryButtonAndSecondaryButtons {
            buttons.switchPrimaryButtonAndSecondaryButtons = switchPrimaryButtonAndSecondaryButtons
        }

        if let clickDebouncing = $clickDebouncing {
            buttons.clickDebouncing = clickDebouncing
        }

        if let gesture = $gesture {
            buttons.$gesture = gesture
        }
    }

    func merge(into buttons: inout Self?) {
        if buttons == nil {
            buttons = Self()
        }

        merge(into: &buttons!)
    }
}

extension Scheme.Buttons.UniversalBackForward: Codable {
    enum ValueError: Error {
        case invalidValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        do {
            self = try container.decode(Bool.self) ? .both : .none
        } catch {
            switch try container.decode(String.self) {
            case "backOnly":
                self = .backOnly
            case "forwardOnly":
                self = .forwardOnly
            default:
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .none:
            try container.encode(false)
        case .both:
            try container.encode(true)
        case .backOnly:
            try container.encode("backOnly")
        case .forwardOnly:
            try container.encode("forwardOnly")
        }
    }
}

extension Scheme.Buttons.UniversalBackForward.ValueError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return NSLocalizedString(
                "UniversalBackForward must be true, false, \"backOnly\" or \"forwardOnly\"",
                comment: ""
            )
        }
    }
}
