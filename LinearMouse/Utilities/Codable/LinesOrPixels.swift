// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

/// Accepts lines (e.g. 3) or pixels (e.g. "12px").
struct LinesOrPixels {
    var value: Int

    enum Unit {
        case line, pixel
    }

    var unit: Unit = .line
}

extension LinesOrPixels: CustomStringConvertible {
    var description: String {
        switch unit {
        case .line:
            return String(value)
        case .pixel:
            return "\(value)px"
        }
    }
}

extension LinesOrPixels: Codable {
    enum ValueError: Error {
        case invalidValue
        case unknownUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            value = try container.decode(Int.self)
        } catch {
            let stringValue = try container.decode(String.self)
            let regex = try NSRegularExpression(pattern: #"^(\d+)(px|)$"#, options: [])

            let matches = regex.matches(
                in: stringValue,
                range: NSRange(stringValue.startIndex ..< stringValue.endIndex, in: stringValue)
            )
            guard let match = matches.first else {
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }

            guard let valueRange = Range(match.range(at: 1), in: stringValue) else {
                throw ValueError.invalidValue
            }

            guard let unitRange = Range(match.range(at: 2), in: stringValue) else {
                throw ValueError.invalidValue
            }

            let valueString = String(stringValue[valueRange])
            let unitString = String(stringValue[unitRange])

            guard let value = Int(valueString, radix: 10) else {
                throw ValueError.invalidValue
            }
            self.value = value

            switch unitString {
            case "":
                unit = .line
            case "px":
                unit = .pixel
            default:
                throw ValueError.unknownUnit
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch unit {
        case .line:
            try container.encode(value)
        case .pixel:
            try container.encode("\(value)px")
        }
    }
}

extension LinesOrPixels.ValueError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return NSLocalizedString(
                "LinesOrPixels must be a number or a string representing value and unit",
                comment: ""
            )
        case .unknownUnit:
            return NSLocalizedString("Unit must be empty or \"px\"", comment: "")
        }
    }
}
