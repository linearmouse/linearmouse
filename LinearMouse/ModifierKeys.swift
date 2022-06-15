// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

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
