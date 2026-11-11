// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme {
    struct Scrolling: Codable, Equatable, ImplicitInitable {
        @ImplicitOptional var reverse: Bidirectional<Bool>
        @ImplicitOptional var distance: Bidirectional<Distance>
        @ImplicitOptional var acceleration: Bidirectional<Decimal>
        @ImplicitOptional var speed: Bidirectional<Decimal>
        @ImplicitOptional var smoothed: Bidirectional<Smoothed>
        // Glide scrolling: destination-based smooth scrolling (see Glide.swift
        // and Documentation/Glide.md).
        @ImplicitOptional var glide: Bidirectional<Glide>
        @ImplicitOptional var modifiers: Bidirectional<Modifiers>

        init() {}

        init(
            reverse: Bidirectional<Bool>? = nil,
            distance: Bidirectional<Distance>? = nil,
            acceleration: Bidirectional<Decimal>? = nil,
            speed: Bidirectional<Decimal>? = nil,
            smoothed: Bidirectional<Smoothed>? = nil,
            glide: Bidirectional<Glide>? = nil,
            modifiers: Bidirectional<Modifiers>? = nil
        ) {
            $reverse = reverse
            $distance = distance
            $acceleration = acceleration
            $speed = speed
            $smoothed = smoothed
            $glide = glide
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
        merge(smoothed: $smoothed, into: &scrolling.smoothed)
        // Glide scrolling: field-by-field merge, defined in Glide.swift.
        merge(glide: $glide, into: &scrolling.glide)
        $modifiers?.merge(into: &scrolling.modifiers)
    }

    func merge(into scrolling: inout Self?) {
        if scrolling == nil {
            scrolling = Self()
        }

        merge(into: &scrolling!)
    }

    private func merge(smoothed source: Bidirectional<Smoothed>?, into target: inout Bidirectional<Smoothed>) {
        guard let source else {
            return
        }

        var merged = target

        if let sourceVertical = source.vertical {
            if merged.vertical == nil {
                merged.vertical = sourceVertical
            } else {
                sourceVertical.merge(into: &merged.vertical!)
            }
        }

        if let sourceHorizontal = source.horizontal {
            if merged.horizontal == nil {
                merged.horizontal = sourceHorizontal
            } else {
                sourceHorizontal.merge(into: &merged.horizontal!)
            }
        }

        target = merged
    }
}
