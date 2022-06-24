// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

@propertyWrapper
struct SingleValueOrArray<Value> where Value: Codable {
    var wrappedValue: [Value]?

    init(wrappedValue value: [Value]?) {
        wrappedValue = value
    }
}

extension SingleValueOrArray: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            wrappedValue = [try container.decode(Value.self)]
        } catch {
            wrappedValue = try container.decode([Value].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let wrappedValue = wrappedValue else {
            try container.encodeNil()
            return
        }
        if wrappedValue.count == 1 {
            try container.encode(wrappedValue[0])
        } else {
            try container.encode(wrappedValue)
        }
    }
}
