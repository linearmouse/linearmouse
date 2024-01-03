// MIT License
// Copyright (c) 2021-2024 LinearMouse

extension Scheme.Scrolling {
    struct Bidirectional<T: Codable & Equatable>: Equatable, ImplicitInitable {
        var vertical: T?
        var horizontal: T?

        func merge(into: inout Self) {
            if let vertical = vertical {
                into.vertical = vertical
            }

            if let horizontal = horizontal {
                into.horizontal = horizontal
            }
        }

        func merge(into: inout Self?) {
            if into == nil {
                into = Self()
            }

            merge(into: &into!)
        }
    }
}

extension Scheme.Scrolling {
    enum BidirectionalDirection: String, Identifiable, CaseIterable {
        var id: Self { self }

        case vertical = "Vertical"
        case horizontal = "Horizontal"
    }
}

extension Scheme.Scrolling.Bidirectional {
    subscript(direction: Scheme.Scrolling.BidirectionalDirection) -> T? {
        get {
            switch direction {
            case .vertical:
                return vertical
            case .horizontal:
                return horizontal
            }
        }
        set {
            switch direction {
            case .vertical:
                vertical = newValue
            case .horizontal:
                horizontal = newValue
            }
        }
    }
}

extension Scheme.Scrolling.Bidirectional: Codable {
    enum CodingKeys: CodingKey {
        case vertical, horizontal
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.vertical) || container.contains(.horizontal) else {
                throw DecodingError.typeMismatch(
                    Self.self,
                    .init(codingPath: container.codingPath,
                          debugDescription: "Neither vertical or horizontal key found")
                )
            }
            vertical = try container.decodeIfPresent(T.self, forKey: .vertical)
            horizontal = try container.decodeIfPresent(T.self, forKey: .horizontal)
        } catch DecodingError.valueNotFound(_, _), DecodingError.typeMismatch(_, _) {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                return
            }
            let v = try container.decode(T?.self)
            vertical = v
            horizontal = v
        }
    }

    func encode(to encoder: Encoder) throws {
        if vertical == horizontal {
            var container = encoder.singleValueContainer()
            try container.encode(vertical)
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        if let vertical = vertical {
            try container.encode(vertical, forKey: .vertical)
        }
        if let horizontal = horizontal {
            try container.encode(horizontal, forKey: .horizontal)
        }
    }
}
