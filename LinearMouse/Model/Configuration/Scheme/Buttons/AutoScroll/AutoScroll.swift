// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme.Buttons {
    struct AutoScroll: Equatable, ImplicitInitable {
        enum Mode: String, Codable, Equatable, CaseIterable, Identifiable {
            var id: Self {
                self
            }

            case toggle
            case hold
        }

        var enabled: Bool?
        var modes: [Mode]?
        var speed: Decimal?
        var preserveNativeMiddleClick: Bool?
        var trigger: Mapping?

        init() {}
    }
}

extension Scheme.Buttons.AutoScroll: Codable {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case speed
        case preserveNativeMiddleClick
        case trigger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        modes = try container.decodeIfPresent(SingleValueOrArray<Mode>.self, forKey: .mode)?.wrappedValue
        speed = try container.decodeIfPresent(Decimal.self, forKey: .speed)
        preserveNativeMiddleClick = try container.decodeIfPresent(Bool.self, forKey: .preserveNativeMiddleClick)
        trigger = try container.decodeIfPresent(Scheme.Buttons.Mapping.self, forKey: .trigger)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encode(SingleValueOrArray(wrappedValue: modes), forKey: .mode)
        try container.encodeIfPresent(speed, forKey: .speed)
        try container.encodeIfPresent(preserveNativeMiddleClick, forKey: .preserveNativeMiddleClick)
        try container.encodeIfPresent(trigger, forKey: .trigger)
    }
}

extension Scheme.Buttons.AutoScroll {
    var normalizedModes: [Mode] {
        let orderedModes = Mode.allCases.filter { modes?.contains($0) == true }
        return orderedModes.isEmpty ? [.toggle] : orderedModes
    }

    var hasToggleMode: Bool {
        normalizedModes.contains(.toggle)
    }

    var hasHoldMode: Bool {
        normalizedModes.contains(.hold)
    }

    func merge(into autoScroll: inout Self) {
        if let enabled {
            autoScroll.enabled = enabled
        }

        if let modes {
            autoScroll.modes = modes
        }

        if let speed {
            autoScroll.speed = speed
        }

        if let preserveNativeMiddleClick {
            autoScroll.preserveNativeMiddleClick = preserveNativeMiddleClick
        }

        if let trigger {
            autoScroll.trigger = trigger
        }
    }

    func merge(into autoScroll: inout Self?) {
        if autoScroll == nil {
            autoScroll = Self()
        }

        merge(into: &autoScroll!)
    }
}
