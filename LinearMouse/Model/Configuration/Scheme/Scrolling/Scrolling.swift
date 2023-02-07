// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension Scheme {
    struct Scrolling: Codable, ImplicitInitable {
        @ImplicitOptional var reverse: Bidirectional<Bool>

        @ImplicitOptional var distance: Bidirectional<Distance>

        @ImplicitOptional var scale: Bidirectional<Decimal>

        @ImplicitOptional var modifiers: Modifiers

        init() {}

        init(reverse: Bidirectional<Bool>? = nil,
             distance: Bidirectional<Distance>? = nil,
             scale: Bidirectional<Decimal>? = nil,
             modifiers: Modifiers? = nil) {
            $reverse = reverse
            $distance = distance
            $scale = scale
            $modifiers = modifiers
        }
    }
}

extension Scheme.Scrolling {
    func merge(into scrolling: inout Self) {
        $reverse?.merge(into: &scrolling.reverse)
        $distance?.merge(into: &scrolling.distance)
        $scale?.merge(into: &scrolling.scale)
        $modifiers?.merge(into: &scrolling.modifiers)
    }

    func merge(into scrolling: inout Self?) {
        if scrolling == nil {
            scrolling = Self()
        }

        merge(into: &scrolling!)
    }
}

extension Scheme.Scrolling {
    struct Bidirectional<T: Codable & Equatable>: ImplicitInitable {
        var value: Value = .init()

        struct Value: Codable {
            var vertical: T?
            var horizontal: T?
        }

        init() {}

        init(vertical: T? = nil, horizontal: T? = nil) {
            value = .init(vertical: vertical, horizontal: horizontal)
        }

        func merge(into: inout Self) {
            if let vertical = value.vertical {
                into.value.vertical = vertical
            }

            if let horizontal = value.horizontal {
                into.value.horizontal = horizontal
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
    var vertical: T? {
        get { value.vertical }
        set { value.vertical = newValue }
    }

    var horizontal: T? {
        get { value.horizontal }
        set { value.horizontal = newValue }
    }

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
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        do {
            value = try container.decode(Value.self)
        } catch {
            let v = try container.decode(T?.self)
            value = .init(vertical: v, horizontal: v)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if value.vertical == value.horizontal {
            try container.encode(value.vertical)
            return
        }

        try container.encode(value)
    }
}
