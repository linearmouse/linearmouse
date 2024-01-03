// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation

struct ModifierKeyAction: Codable {
    var type: ModifierKeyActionType
    var speedFactor: Double
}

enum ModifierKeyActionType: String, Codable, CaseIterable {
    case noAction = "No action"
    case alterOrientation = "Alter orientation"
    case changeSpeed = "Change speed"
}

extension ModifierKeyAction {
    var schemeAction: Scheme.Scrolling.Modifiers.Action {
        switch type {
        case .noAction:
            return .preventDefault
        case .alterOrientation:
            return .alterOrientation
        case .changeSpeed:
            return .changeSpeed(scale: Decimal(speedFactor))
        }
    }
}
