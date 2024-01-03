// MIT License
// Copyright (c) 2021-2024 LinearMouse

// SwiftFormat will eat the empty lines between the file header and @propertyWrapper.
// These comments should be removed when SwiftFormat fixes this bug.

@propertyWrapper
struct SingleValueOrArray<Value> where Value: Codable {
    var wrappedValue: [Value]?

    init(wrappedValue value: [Value]?) {
        wrappedValue = value
    }
}

extension SingleValueOrArray: CustomStringConvertible {
    var description: String {
        wrappedValue?.description ?? "nil"
    }
}

extension SingleValueOrArray: Equatable where Value: Equatable {}

extension SingleValueOrArray: Hashable where Value: Hashable {}

extension SingleValueOrArray: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            wrappedValue = try container.decode([Value].self)
        } catch {
            wrappedValue = try [container.decode(Value.self)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = wrappedValue, value.count == 1 {
            try container.encode(value[0])
        } else {
            try container.encode(wrappedValue)
        }
    }
}

extension KeyedDecodingContainer {
    func decode<Value: Codable>(_ type: SingleValueOrArray<Value>.Type,
                                forKey key: Self.Key) throws -> SingleValueOrArray<Value> {
        try decodeIfPresent(type, forKey: key) ?? SingleValueOrArray(wrappedValue: nil)
    }
}

extension KeyedEncodingContainer {
    mutating func encode<Value: Codable>(_ value: SingleValueOrArray<Value>, forKey key: Self.Key) throws {
        guard value.wrappedValue != nil else {
            return
        }

        // Call `encodeIfPresent` instead of `encode` to avoid infinite recursive.
        // Probably not the best practice?
        try encodeIfPresent(value, forKey: key)
    }
}
