// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension Scheme {
    struct Buttons: Codable {
        var mappings: [Mapping]?

        enum UniversalBackForward {
            case none
            case both
            case backOnly
            case forwardOnly
        }

        var universalBackForward: UniversalBackForward?
    }
}

extension Scheme.Buttons {
    func merge(into buttons: inout Self) {
        if let mappings = mappings, mappings.count > 0 {
            buttons.mappings = (buttons.mappings ?? []) + mappings
        }

        if let universalBackForward = universalBackForward {
            buttons.universalBackForward = universalBackForward
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
