// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation

extension Scheme.Scrolling {
    enum Distance: Equatable, Hashable {
        case auto
        case line(Int)
        case pixel(Decimal)
    }
}

extension Scheme.Scrolling.Distance: CustomStringConvertible {
    var description: String {
        switch self {
        case .auto:
            return NSLocalizedString("auto", comment: "")
        case let .line(value):
            return String(format: NSLocalizedString("%d line(s)", comment: ""), value)
        case let .pixel(value):
            return String(format: NSLocalizedString("%.1f pixel(s)", comment: ""), value.asTruncatedDouble)
        }
    }
}

extension Scheme.Scrolling.Distance: Codable {
    enum ValueError: Error {
        case invalidValue
        case unknownUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            let value = try container.decode(Int.self)
            self = .line(value)
        } catch {
            let stringValue = try container.decode(String.self)

            if stringValue == "auto" {
                self = .auto
                return
            }

            let regex = try NSRegularExpression(pattern: #"^([\d.]+)(px|)$"#, options: [])

            let matches = regex.matches(
                in: stringValue,
                range: NSRange(stringValue.startIndex ..< stringValue.endIndex, in: stringValue)
            )
            guard let match = matches.first else {
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }

            guard let valueRange = Range(match.range(at: 1), in: stringValue) else {
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }

            guard let unitRange = Range(match.range(at: 2), in: stringValue) else {
                throw CustomDecodingError(in: container, error: ValueError.invalidValue)
            }

            let valueString = String(stringValue[valueRange])
            let unitString = String(stringValue[unitRange])

            switch unitString {
            case "":
                guard let value = Int(valueString, radix: 10) else {
                    throw CustomDecodingError(in: container, error: ValueError.invalidValue)
                }

                self = .line(value)

            case "px":
                guard let value = Decimal(string: valueString) else {
                    throw CustomDecodingError(in: container, error: ValueError.invalidValue)
                }

                self = .pixel(value)

            default:
                throw CustomDecodingError(in: container, error: ValueError.unknownUnit)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .auto:
            try container.encode("auto")
        case let .line(value):
            try container.encode(value)
        case let .pixel(value):
            try container.encode("\(value)px")
        }
    }
}

extension Scheme.Scrolling.Distance.ValueError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return NSLocalizedString(
                "Distance must be \"auto\" or a number or a string representing value and unit",
                comment: ""
            )
        case .unknownUnit:
            return NSLocalizedString("Unit must be empty or \"px\"", comment: "")
        }
    }
}
