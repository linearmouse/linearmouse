//
//  ModifierKeys.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/7/29.
//

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
