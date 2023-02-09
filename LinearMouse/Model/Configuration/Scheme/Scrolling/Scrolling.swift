// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension Scheme {
    struct Scrolling: Codable, ImplicitInitable {
        @ImplicitOptional var reverse: Bidirectional<Bool>
        @ImplicitOptional var distance: Bidirectional<Distance>
        @ImplicitOptional var acceleration: Bidirectional<Decimal>
        @ImplicitOptional var speed: Bidirectional<Decimal>
        @ImplicitOptional var modifiers: Bidirectional<Modifiers>

        init() {}

        init(reverse: Bidirectional<Bool>? = nil,
             distance: Bidirectional<Distance>? = nil,
             acceleration: Bidirectional<Decimal>? = nil,
             speed: Bidirectional<Decimal>? = nil,
             modifiers: Bidirectional<Modifiers>? = nil) {
            $reverse = reverse
            $distance = distance
            $acceleration = acceleration
            $speed = speed
            $modifiers = modifiers
        }
    }
}

extension Scheme.Scrolling {
    func merge(into scrolling: inout Self) {
        $reverse?.merge(into: &scrolling.reverse)
        $distance?.merge(into: &scrolling.distance)
        $acceleration?.merge(into: &scrolling.acceleration)
        $speed?.merge(into: &scrolling.speed)
        $modifiers?.merge(into: &scrolling.modifiers)
    }

    func merge(into scrolling: inout Self?) {
        if scrolling == nil {
            scrolling = Self()
        }

        merge(into: &scrolling!)
    }
}
