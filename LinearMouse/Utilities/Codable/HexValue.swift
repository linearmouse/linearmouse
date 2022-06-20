// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

struct HexValue: Equatable {
    var value: Int
}

extension HexValue {
    init?(_ value: Int?) {
        guard let value = value else { return nil }
        self.value = value
    }
}

extension HexValue: Codable {
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
            guard let parsedValue = Int(hexValue, radix: 16) else {
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }
            value = parsedValue
        } catch {
            value = try container.decode(Int.self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("0x" + String(value, radix: 16))
    }
}

extension HexValue: CustomStringConvertible {
    var description: String {
        value.description
    }
}

extension HexValue.ValueError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return NSLocalizedString("Invalid value", comment: "")
        }
    }
}
