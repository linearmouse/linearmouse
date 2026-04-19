// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import SwiftUI

extension Scheme.Scrolling {
    struct Smoothed: Equatable, Codable, ImplicitInitable {
        struct PresetProfile: Equatable {
            var response: Double
            var inputExponent: Double
            var accelerationGain: Double
            var decay: Double
            var velocityScale: Double
        }

        enum Preset: String, Codable, Equatable, CaseIterable, Identifiable {
            var id: Self {
                self
            }

            case custom
            case linear
            case easeIn
            case easeOut
            case easeInOut
            case quadratic
            case cubic
            case quartic
            case easeOutCubic
            case easeInOutCubic
            case easeOutQuartic
            case easeInOutQuartic
            case smooth
        }

        var enabled: Bool?
        var preset: Preset?
        var response: Decimal?
        var speed: Decimal?
        var acceleration: Decimal?
        var inertia: Decimal?

        init() {}

        init(
            enabled: Bool? = nil,
            preset: Preset? = nil,
            response: Decimal? = nil,
            speed: Decimal? = nil,
            acceleration: Decimal? = nil,
            inertia: Decimal? = nil
        ) {
            self.enabled = enabled
            self.preset = preset
            self.response = response
            self.speed = speed
            self.acceleration = acceleration
            self.inertia = inertia
        }
    }
}

extension Scheme.Scrolling.Smoothed {
    static let responseRange: ClosedRange<Double> = 0.0 ... 2.0
    static let speedRange: ClosedRange<Double> = 0.0 ... 8.0
    static let accelerationRange: ClosedRange<Double> = 0.0 ... 8.0
    static let inertiaRange: ClosedRange<Double> = 0.0 ... 8.0

    var resolvedPreset: Preset {
        preset ?? .defaultPreset
    }

    var resolvedPresetProfile: PresetProfile {
        resolvedPreset.profile
    }

    var isEnabled: Bool {
        enabled ?? true
    }

    func merge(into smoothed: inout Self) {
        if let enabled {
            smoothed.enabled = enabled
        }

        if let preset {
            smoothed.preset = preset
        }

        if let response {
            smoothed.response = response
        }

        if let speed {
            smoothed.speed = speed
        }

        if let acceleration {
            smoothed.acceleration = acceleration
        }

        if let inertia {
            smoothed.inertia = inertia
        }
    }

    func merge(into smoothed: inout Self?) {
        if smoothed == nil {
            smoothed = Self()
        }

        merge(into: &smoothed!)
    }
}

extension Scheme.Scrolling.Smoothed.Preset {
    struct Presentation: Equatable {
        var title: LocalizedStringKey
        var subtitle: LocalizedStringKey
        var showsEditableBadge = false
    }

    static var defaultPreset: Self {
        .easeInOut
    }

    static var recommendedCases: [Self] {
        [
            .easeInOut,
            .easeIn,
            .easeOut,
            .linear,
            .quadratic,
            .cubic,
            .easeOutCubic,
            .easeInOutCubic,
            .quartic,
            .easeOutQuartic,
            .easeInOutQuartic,
            .smooth,
            .custom
        ]
    }

    var profile: Scheme.Scrolling.Smoothed.PresetProfile {
        switch self {
        case .custom:
            return .init(response: 0.64, inputExponent: 1.00, accelerationGain: 0.10, decay: 0.89, velocityScale: 32)
        case .linear:
            return .init(response: 0.94, inputExponent: 0.96, accelerationGain: 0.04, decay: 0.83, velocityScale: 34)
        case .easeIn:
            return .init(response: 0.34, inputExponent: 1.18, accelerationGain: 0.08, decay: 0.93, velocityScale: 24)
        case .easeOut:
            return .init(response: 0.90, inputExponent: 0.92, accelerationGain: 0.08, decay: 0.84, velocityScale: 34)
        case .easeInOut:
            return .init(response: 0.68, inputExponent: 1.06, accelerationGain: 0.10, decay: 0.89, velocityScale: 31)
        case .quadratic:
            return .init(response: 0.58, inputExponent: 1.12, accelerationGain: 0.12, decay: 0.88, velocityScale: 33)
        case .cubic:
            return .init(response: 0.52, inputExponent: 1.18, accelerationGain: 0.14, decay: 0.89, velocityScale: 35)
        case .quartic:
            return .init(response: 0.46, inputExponent: 1.24, accelerationGain: 0.16, decay: 0.90, velocityScale: 37)
        case .easeOutCubic:
            return .init(response: 0.94, inputExponent: 0.86, accelerationGain: 0.08, decay: 0.82, velocityScale: 35)
        case .easeInOutCubic:
            return .init(response: 0.62, inputExponent: 1.12, accelerationGain: 0.12, decay: 0.89, velocityScale: 33)
        case .easeOutQuartic:
            return .init(response: 0.98, inputExponent: 0.80, accelerationGain: 0.08, decay: 0.80, velocityScale: 36)
        case .easeInOutQuartic:
            return .init(response: 0.56, inputExponent: 1.18, accelerationGain: 0.14, decay: 0.90, velocityScale: 34)
        case .smooth:
            return .init(response: 0.80, inputExponent: 0.98, accelerationGain: 0.06, decay: 0.93, velocityScale: 33)
        }
    }

    var presentation: Presentation {
        switch self {
        case .custom:
            return .init(
                title: "Custom",
                subtitle: "Use this when you want to fine-tune the feel yourself.",
                showsEditableBadge: true
            )
        case .linear:
            return .init(title: "Linear", subtitle: "Direct and immediate, with a short controlled tail.")
        case .easeIn:
            return .init(title: "Ease In", subtitle: "Soft start that builds momentum as you keep scrolling.")
        case .easeOut:
            return .init(title: "Ease Out", subtitle: "Fast initial response that settles quickly.")
        case .easeInOut:
            return .init(title: "Ease In Out", subtitle: "Balanced ramp-up and release.")
        case .quadratic:
            return .init(title: "Ease In Quad", subtitle: "Ease-in quad with a noticeable but manageable ramp-up.")
        case .cubic:
            return .init(title: "Ease In Cubic", subtitle: "Ease-in cubic with a stronger progressive build.")
        case .quartic:
            return .init(title: "Ease In Quartic", subtitle: "Ease-in quartic with the strongest front-loaded ramp.")
        case .easeOutCubic:
            return .init(title: "Ease Out Cubic", subtitle: "Fast cubic pickup that settles into a shorter tail.")
        case .easeInOutCubic:
            return .init(title: "Ease In Out Cubic", subtitle: "Cubic ease-in-out with a weightier middle section.")
        case .easeOutQuartic:
            return .init(title: "Ease Out Quartic", subtitle: "Very fast quartic pickup with a crisp release.")
        case .easeInOutQuartic:
            return .init(title: "Ease In Out Quartic", subtitle: "Quartic ease-in-out with the boldest mid-curve.")
        case .smooth:
            return .init(title: "Smooth", subtitle: "Stable and fluid, with a longer carry than Linear.")
        }
    }

    var defaultConfiguration: Scheme.Scrolling.Smoothed {
        let values: (response: Decimal, speed: Decimal, acceleration: Decimal, inertia: Decimal)

        switch self {
        case .custom:
            values = (0.68, 1.00, 1.00, 0.80)
        case .linear:
            values = (0.92, 1.00, 0.78, 0.44)
        case .easeIn:
            values = (0.38, 0.92, 0.86, 1.00)
        case .easeOut:
            values = (0.88, 1.02, 0.94, 0.42)
        case .easeInOut:
            values = (0.68, 1.02, 1.10, 0.74)
        case .quadratic:
            values = (0.58, 1.04, 1.18, 0.72)
        case .cubic:
            values = (0.54, 1.08, 1.24, 0.76)
        case .quartic:
            values = (0.48, 1.12, 1.32, 0.82)
        case .easeOutCubic:
            values = (0.94, 1.06, 0.92, 0.42)
        case .easeInOutCubic:
            values = (0.62, 1.06, 1.20, 0.78)
        case .easeOutQuartic:
            values = (0.98, 1.10, 0.90, 0.38)
        case .easeInOutQuartic:
            values = (0.56, 1.10, 1.28, 0.82)
        case .smooth:
            values = (0.80, 1.00, 0.88, 0.92)
        }

        return .init(
            enabled: true,
            preset: self,
            response: values.response,
            speed: values.speed,
            acceleration: values.acceleration,
            inertia: values.inertia
        )
    }
}
