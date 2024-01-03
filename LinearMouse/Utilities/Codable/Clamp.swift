// MIT License
// Copyright (c) 2021-2024 LinearMouse

protocol ClampRange {
    associatedtype Value: Codable, Comparable

    static var range: ClosedRange<Value> { get }
}

@propertyWrapper
struct Clamp<T: ClampRange> {
    private var value: T.Value?

    var wrappedValue: T.Value? {
        get { value }
        set {
            value = newValue.map { $0.clamped(to: T.range) }
        }
    }

    init(wrappedValue value: T.Value?) {
        wrappedValue = value
    }
}

extension Clamp: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(T.Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension Clamp: Equatable where T: Equatable {}

extension KeyedDecodingContainer {
    func decode<T: ClampRange>(_ type: Clamp<T>.Type,
                               forKey key: Self.Key) throws -> Clamp<T> {
        try decodeIfPresent(type, forKey: key) ?? Clamp<T>(wrappedValue: nil)
    }
}

extension KeyedEncodingContainer {
    mutating func encode<T: ClampRange>(_ value: Clamp<T>,
                                        forKey key: Self.Key) throws {
        guard value.wrappedValue != nil else {
            return
        }

        try encodeIfPresent(value, forKey: key)
    }
}
