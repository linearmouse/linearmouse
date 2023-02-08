// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import SwiftUI

extension ScrollingSettings.ModifierKeysSection {
    struct ModifierKeyActionPicker: View {
        var label: LocalizedStringKey
        @Binding var action: Scheme.Scrolling.Modifiers.Action?

        var body: some View {
            Picker(label, selection: actionType) {
                ForEach(ActionType.allCases) { type in
                    Text(NSLocalizedString(type.rawValue, comment: "")).tag(type)
                }
            }
            .modifier(PickerViewModifier())

            if case .some(.changeSpeed) = action {
                HStack {
                    Slider(value: self.speedFactor,
                           in: 0.05 ... 10.00)
                    HStack(spacing: 5) {
                        Text(String(format: "%0.2f ×", self.speedFactor.wrappedValue))
                    }
                    .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }
}

extension ScrollingSettings.ModifierKeysSection.ModifierKeyActionPicker {
    enum ActionType: String, CaseIterable, Identifiable {
        var id: Self { self }

        case noAction = "No action"
        case alterOrientation = "Alter orientation"
        case changeSpeed = "Change speed"
        case zoom = "Zoom"
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
                case .zoom:
                    return .zoom
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
                case .zoom:
                    self.action = .zoom
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
