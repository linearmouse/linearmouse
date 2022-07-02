// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

extension Scheme {
    struct Scrolling: Codable {
        struct Reverse: Codable {
            var vertical: Bool?
            var horizontal: Bool?
        }

        var reverse: Reverse?

        var distance: Distance?

        var modifiers: Modifiers?
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

extension Scheme.Scrolling.Reverse {
    func merge(into reverse: inout Self) {
        if let vertical = vertical {
            reverse.vertical = vertical
        }

        if let horizontal = horizontal {
            reverse.horizontal = horizontal
        }
    }

    func merge(into reverse: inout Self?) {
        if reverse == nil {
            reverse = Self()
        }

        merge(into: &reverse!)
    }
}
