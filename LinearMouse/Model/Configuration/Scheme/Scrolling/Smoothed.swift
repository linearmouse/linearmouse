// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

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
            case easeOutIn
            case quadratic
            case cubic
            case quartic
            case easeOutCubic
            case easeInOutCubic
            case easeOutQuartic
            case easeInOutQuartic
            case quintic
            case sine
            case exponential
            case circular
            case back
            case bounce
            case elastic
            case spring
            case natural
            case smooth
            case snappy
            case gentle
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
        case .easeOutIn:
            return .init(response: 0.62, inputExponent: 0.98, accelerationGain: 0.10, decay: 0.87, velocityScale: 30)
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
        case .quintic:
            return .init(response: 0.40, inputExponent: 1.30, accelerationGain: 0.18, decay: 0.91, velocityScale: 39)
        case .sine:
            return .init(response: 0.74, inputExponent: 0.98, accelerationGain: 0.08, decay: 0.90, velocityScale: 30)
        case .exponential:
            return .init(response: 0.36, inputExponent: 1.34, accelerationGain: 0.20, decay: 0.92, velocityScale: 40)
        case .circular:
            return .init(response: 0.50, inputExponent: 1.14, accelerationGain: 0.14, decay: 0.91, velocityScale: 35)
        case .back:
            return .init(response: 0.60, inputExponent: 1.04, accelerationGain: 0.13, decay: 0.85, velocityScale: 31)
        case .bounce:
            return .init(response: 0.78, inputExponent: 0.94, accelerationGain: 0.08, decay: 0.80, velocityScale: 27)
        case .elastic:
            return .init(response: 0.44, inputExponent: 1.10, accelerationGain: 0.14, decay: 0.95, velocityScale: 36)
        case .spring:
            return .init(response: 0.88, inputExponent: 0.96, accelerationGain: 0.11, decay: 0.91, velocityScale: 36)
        case .natural:
            return .init(response: 0.86, inputExponent: 0.98, accelerationGain: 0.08, decay: 0.86, velocityScale: 32)
        case .smooth:
            return .init(response: 0.80, inputExponent: 0.98, accelerationGain: 0.06, decay: 0.93, velocityScale: 33)
        case .snappy:
            return .init(response: 1.00, inputExponent: 0.88, accelerationGain: 0.05, decay: 0.76, velocityScale: 32)
        case .gentle:
            return .init(response: 0.42, inputExponent: 1.00, accelerationGain: 0.05, decay: 0.97, velocityScale: 34)
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
        case .easeOutIn:
            values = (0.62, 1.00, 1.08, 0.70)
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
        case .quintic:
            values = (0.42, 1.16, 1.40, 0.88)
        case .sine:
            values = (0.74, 1.00, 0.92, 0.72)
        case .exponential:
            values = (0.36, 1.18, 1.55, 0.92)
        case .circular:
            values = (0.52, 1.06, 1.26, 0.84)
        case .back:
            values = (0.60, 1.04, 1.16, 0.58)
        case .bounce:
            values = (0.80, 0.96, 0.88, 0.34)
        case .elastic:
            values = (0.44, 1.10, 1.22, 1.08)
        case .spring:
            values = (0.86, 1.06, 1.08, 0.96)
        case .natural:
            values = (0.84, 1.00, 0.96, 0.58)
        case .smooth:
            values = (0.80, 1.00, 0.88, 0.92)
        case .snappy:
            values = (0.98, 1.00, 0.78, 0.24)
        case .gentle:
            values = (0.42, 0.94, 0.76, 1.18)
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
