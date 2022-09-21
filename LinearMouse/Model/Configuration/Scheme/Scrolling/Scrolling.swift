// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

extension Scheme {
    struct Scrolling: Codable {
        var reverse: Bidirectional<Bool>?

        var distance: Distance?

        var modifiers: Modifiers?
    }
}

extension Scheme.Scrolling {
    struct Bidirectional<T: Codable>: Codable {
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
    func merge(into scrolling: inout Self) {
        if let reverse = reverse {
            reverse.merge(into: &scrolling.reverse)
        }

        if let distance = distance {
            scrolling.distance = distance
        }

        if let modifiers = modifiers {
            modifiers.merge(into: &scrolling.modifiers)
        }
    }

    func merge(into scrolling: inout Self?) {
        if scrolling == nil {
            scrolling = Self()
        }

        merge(into: &scrolling!)
    }
}
