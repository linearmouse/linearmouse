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
            var left: Mapping.Action.Arg0?
            var right: Mapping.Action.Arg0?
            var up: Mapping.Action.Arg0?
            var down: Mapping.Action.Arg0?
        }
    }
}
