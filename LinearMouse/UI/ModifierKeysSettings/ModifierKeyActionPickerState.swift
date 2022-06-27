// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import SwiftUI

extension ModifierKeyActionPicker {
    enum ActionType: String, CaseIterable, Identifiable {
        var id: Self { self }

        case noAction = "No action"
        case alterOrientation = "Alter orientation"
        case changeSpeed = "Change speed"
    }

    var actionType: Binding<ActionType> {
        Binding<ActionType>(
            get: {
                guard let action = action else {
                    return .noAction
                }

                switch action {
                case .none:
                    return .noAction
                case .alterOrientation:
                    return .alterOrientation
                case .changeSpeed:
                    return .changeSpeed
                }
            },

            set: { action in
                switch action {
                case .noAction:
                    self.action = Scheme.Scrolling.Modifiers.Action.none
                case .alterOrientation:
                    self.action = .alterOrientation
                case .changeSpeed:
                    self.action = .changeSpeed(scale: 1)
                }
            }
        )
    }

    var speedFactor: Binding<Double> {
        Binding<Double>(
            get: {
                guard case let .changeSpeed(speedFactor) = action else {
                    return 1
                }

                return speedFactor.asTruncatedDouble
            },

            set: { value in
                if value < 0 {
                    action = .changeSpeed(scale: Decimal(value).rounded(0))
                } else if 0 ..< 0.1 ~= value {
                    action = .changeSpeed(scale: Decimal(value * 20).rounded(0) / 20)
                } else if 0.1 ..< 1 ~= value {
                    action = .changeSpeed(scale: Decimal(value).rounded(1))
                } else {
                    action = .changeSpeed(scale: Decimal(value * 2).rounded(0) / 2)
                }
            }
        )
    }
}
