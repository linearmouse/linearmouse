// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ModifierKeysSettings: View {
    @ObservedObject var schemeState = SchemeState.shared

    var body: some View {
        DetailView {
            Form {
                Section {
                    ModifierKeyActionPicker(label: "⌘ (Command)", action: $schemeState.commandAction)
                    ModifierKeyActionPicker(label: "⇧ (Shift)", action: $schemeState.shiftAction)
                    ModifierKeyActionPicker(label: "⌥ (Option)", action: $schemeState.optionAction)
                    ModifierKeyActionPicker(label: "⌃ (Control)", action: $schemeState.controlAction)
                }
                .modifier(SectionViewModifier())
            }
            .modifier(FormViewModifier())
        }
    }
}
