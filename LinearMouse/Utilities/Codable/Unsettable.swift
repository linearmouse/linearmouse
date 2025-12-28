// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

enum Unsettable<T: Codable & Equatable>: Equatable, Codable {
    case value(T)
    case unset

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try decoding the sentinel string "unset"
        if let string = try? container.decode(String.self), string == "unset" {
            self = .unset
            return
        }

        // Otherwise, decode the underlying value
        let value = try container.decode(T.self)
        self = .value(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .value(value):
            try container.encode(value)
        case .unset:
            try container.encode("unset")
        }
    }
}

extension Unsettable {
    var unwrapped: T? {
        if case let .value(value) = self {
            return value
        }
        return nil
    }
}
