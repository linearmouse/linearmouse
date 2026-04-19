// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import SwiftUI

extension ScrollingSettings.ModifierKeysSection {
    struct ModifierKeyActionPicker: View {
        var label: LocalizedStringKey
        @Binding var action: Scheme.Scrolling.Modifiers.Action?

        var body: some View {
            Picker(label, selection: $action.kind) {
                ForEach(ActionType.allCases) { type in
                    type.label.tag(type)
                    if type == .defaultAction || type == .noAction {
                        Divider()
                    }
                }
            }
            .modifier(PickerViewModifier())

            if case .some(.changeSpeed) = action {
                HStack(spacing: 5) {
                    Slider(
                        value: $action.speedFactor,
                        in: 0.05 ... 10.00
                    )
                    .labelsHidden()
                    Text(verbatim: String(format: "%0.2f ×", $action.speedFactor.wrappedValue))
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }
}

extension ScrollingSettings.ModifierKeysSection.ModifierKeyActionPicker {
    typealias ActionType = Scheme.Scrolling.Modifiers.Action.Kind
}
