// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

extension Scheme.Buttons.Gesture {
    enum GestureAction: String, Codable, Equatable, Identifiable, CaseIterable {
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
