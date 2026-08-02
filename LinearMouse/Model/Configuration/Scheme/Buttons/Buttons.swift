// MIT License
// Copyright (c) 2021-2026 LinearMouse

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

        @ImplicitOptional var autoScroll: AutoScroll

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
            clickDebouncing.merge(into: &buttons.$clickDebouncing)
        }

        if let autoScroll = $autoScroll {
            autoScroll.merge(into: &buttons.$autoScroll)
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

extension Scheme.Buttons {
    private enum CodingKeys: String, CodingKey {
        case mappings
        case universalBackForward
        case switchPrimaryButtonAndSecondaryButtons
        case clickDebouncing
        case autoScroll
        case gesture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappings = try container.decodeIfPresent([Mapping].self, forKey: .mappings)?.map { mapping in
            var mapping = mapping
            mapping.normalizeAsStructured()
            return mapping
        }
        universalBackForward = try container.decodeIfPresent(
            UniversalBackForward.self,
            forKey: .universalBackForward
        )
        switchPrimaryButtonAndSecondaryButtons = try container.decodeIfPresent(
            Bool.self,
            forKey: .switchPrimaryButtonAndSecondaryButtons
        )
        _clickDebouncing = try container.decode(
            ImplicitOptional<ClickDebouncing>.self,
            forKey: .clickDebouncing
        )
        _autoScroll = try container.decode(ImplicitOptional<AutoScroll>.self, forKey: .autoScroll)
        _gesture = try container.decode(ImplicitOptional<Gesture>.self, forKey: .gesture)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let normalizedMappings = mappings?.map { mapping in
            var mapping = mapping
            mapping.normalizeAsStructured()
            return mapping
        }
        try container.encodeIfPresent(normalizedMappings, forKey: .mappings)
        try container.encodeIfPresent(universalBackForward, forKey: .universalBackForward)
        try container.encodeIfPresent(
            switchPrimaryButtonAndSecondaryButtons,
            forKey: .switchPrimaryButtonAndSecondaryButtons
        )
        try container.encode(_clickDebouncing, forKey: .clickDebouncing)
        try container.encode(_autoScroll, forKey: .autoScroll)
        try container.encode(_gesture, forKey: .gesture)
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
