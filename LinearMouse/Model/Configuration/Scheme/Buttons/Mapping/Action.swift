// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

extension Scheme.Buttons.Mapping {
    enum Action {
        case auto
        case none
        case run(String)
    }
}

extension Scheme.Buttons.Mapping.Action: Codable {
    enum ValueError: Error {
        case invalidValue
    }

    enum CodingKeys: String, CodingKey {
        case run
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()

            switch try container.decode(String.self) {
            case "auto":
                self = .auto

            case "none":
                self = .none

            default:
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }
        } catch {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let command = try container.decode(String.self, forKey: .run)

            self = .run(command)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .auto:
            var container = encoder.singleValueContainer()
            try container.encode("auto")

        case .none:
            var container = encoder.singleValueContainer()
            try container.encode("none")

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
            return NSLocalizedString(#"Action must be "auto", "none" or { "run": "<command>" }"#, comment: "")
        }
    }
}
