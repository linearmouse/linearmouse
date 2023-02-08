// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension Scheme {
    struct Scrolling: Codable, ImplicitInitable {
        @ImplicitOptional var reverse: Bidirectional<Bool>
        @ImplicitOptional var distance: Bidirectional<Distance>
        @ImplicitOptional var scale: Bidirectional<Decimal>
        @ImplicitOptional var discrete: Bidirectional<Bool>
        @ImplicitOptional var modifiers: Bidirectional<Modifiers>

        init() {}

        init(reverse: Bidirectional<Bool>? = nil,
             distance: Bidirectional<Distance>? = nil,
             scale: Bidirectional<Decimal>? = nil,
             discrete: Bidirectional<Bool>? = nil,
             modifiers: Bidirectional<Modifiers>? = nil) {
            $reverse = reverse
            $distance = distance
            $scale = scale
            $discrete = discrete
            $modifiers = modifiers
        }
    }
}

extension Scheme.Scrolling {
    func merge(into scrolling: inout Self) {
        $reverse?.merge(into: &scrolling.reverse)
        $distance?.merge(into: &scrolling.distance)
        $scale?.merge(into: &scrolling.scale)
        $discrete?.merge(into: &scrolling.discrete)
        $modifiers?.merge(into: &scrolling.modifiers)
    }

    func merge(into scrolling: inout Self?) {
        if scrolling == nil {
            scrolling = Self()
        }

        merge(into: &scrolling!)
    }
}
