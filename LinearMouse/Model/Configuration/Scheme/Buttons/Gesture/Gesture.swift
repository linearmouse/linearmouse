// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme.Buttons {
    struct Gesture: Equatable, ImplicitInitable {
        var enabled: Bool?
        var trigger: Mapping?
        var threshold: Int?
        var deadZone: Int?
        var cooldownMs: Int?

        @ImplicitOptional var actions: Actions

        struct Actions: Codable, Equatable, ImplicitInitable {
            var left: GestureAction?
            var right: GestureAction?
            var up: GestureAction?
            var down: GestureAction?
        }

        enum GestureAction: String, Codable, Equatable, Hashable, Identifiable, CaseIterable {
            var id: Self {
                self
            }

            case none
            case spaceLeft = "missionControl.spaceLeft"
            case spaceRight = "missionControl.spaceRight"
            case missionControl
            case appExpose
            case showDesktop
            case launchpad
        }
    }
}

extension Scheme.Buttons.Gesture: Codable {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case trigger
        case button
        case threshold
        case deadZone
        case cooldownMs
        case actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        trigger = try container.decodeIfPresent(Scheme.Buttons.Mapping.self, forKey: .trigger)
        threshold = try container.decodeIfPresent(Int.self, forKey: .threshold)
        deadZone = try container.decodeIfPresent(Int.self, forKey: .deadZone)
        cooldownMs = try container.decodeIfPresent(Int.self, forKey: .cooldownMs)
        _actions = try container.decodeIfPresent(ImplicitOptional<Actions>.self, forKey: .actions) ?? .init()

        // Migrate legacy "button" field to "trigger"
        if trigger == nil, let button = try container.decodeIfPresent(Int.self, forKey: .button) {
            var mapping = Scheme.Buttons.Mapping()
            mapping.button = .mouse(button)
            trigger = mapping
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(trigger, forKey: .trigger)
        try container.encodeIfPresent(threshold, forKey: .threshold)
        try container.encodeIfPresent(deadZone, forKey: .deadZone)
        try container.encodeIfPresent(cooldownMs, forKey: .cooldownMs)
        try container.encodeIfPresent($actions, forKey: .actions)
    }
}
