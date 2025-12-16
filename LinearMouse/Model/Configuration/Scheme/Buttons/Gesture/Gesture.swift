// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

extension Scheme.Buttons {
    struct Gesture: Codable, Equatable, ImplicitInitable {
        var enabled: Bool?
        var button: Int?
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
            var id: Self { self }

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
