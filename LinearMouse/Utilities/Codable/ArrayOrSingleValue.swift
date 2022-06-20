// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

struct ArrayOrSingleValue<T> where T: Codable {
    var value: [T]
}

extension ArrayOrSingleValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            value = [try container.decode(T.self)]
        } catch {
            value = try container.decode([T].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value.count == 1 {
            try container.encode(value[0])
        } else {
            try container.encode(value)
        }
    }
}
