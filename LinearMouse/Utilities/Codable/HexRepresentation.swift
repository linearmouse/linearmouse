// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

@propertyWrapper
struct HexRepresentation<Value: BinaryInteger & Codable>: Equatable {
    var wrappedValue: Value?

    init(wrappedValue value: Value?) {
        wrappedValue = value
    }
}

extension HexRepresentation: Codable {
    enum ValueError: Error {
        case invalidValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            var hexValue = try container.decode(String.self)
            if hexValue.hasPrefix("0x") {
                hexValue = String(hexValue.dropFirst(2))
            }
            guard let parsedValue = Int64(hexValue, radix: 16) else {
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }
            wrappedValue = Value(parsedValue)
        } catch {
            wrappedValue = try container.decode(Value.self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let wrappedValue = wrappedValue else {
            try container.encodeNil()
            return
        }
        try container.encode("0x" + String(wrappedValue, radix: 16))
    }
}

extension HexRepresentation.ValueError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return NSLocalizedString("Invalid value", comment: "")
        }
    }
}
