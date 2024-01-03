// MIT License
// Copyright (c) 2021-2024 LinearMouse

protocol ImplicitInitable {
    init()
}

@propertyWrapper
struct ImplicitOptional<WrappedValue: ImplicitInitable> {
    var projectedValue: WrappedValue?

    var wrappedValue: WrappedValue {
        get { projectedValue ?? .init() }
        set { projectedValue = newValue }
    }

    init() {}

    init(wrappedValue: WrappedValue) {
        self.wrappedValue = wrappedValue
    }
}

extension ImplicitOptional: ExpressibleByNilLiteral {
    init(nilLiteral _: ()) {}
}

extension ImplicitOptional: Equatable where WrappedValue: Equatable {}

extension ImplicitOptional: Encodable where WrappedValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(projectedValue)
    }
}

extension ImplicitOptional: Decodable where WrappedValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        projectedValue = try container.decode(WrappedValue?.self)
    }
}

extension KeyedEncodingContainer {
    mutating func encode<WrappedValue: Encodable & ImplicitInitable>(_ value: ImplicitOptional<WrappedValue>,
                                                                     forKey key: Self.Key) throws {
        guard value.projectedValue != nil else {
            return
        }

        // Call `encodeIfPresent` instead of `encode` to avoid infinite recursive.
        // Probably not the best practice?
        try encodeIfPresent(value.projectedValue, forKey: key)
    }
}

extension KeyedDecodingContainer {
    func decode<WrappedValue: Decodable & ImplicitInitable>(
        _ type: ImplicitOptional<WrappedValue>.Type,
        forKey key: Self.Key
    ) throws -> ImplicitOptional<WrappedValue> {
        try decodeIfPresent(type, forKey: key) ?? nil
    }
}
