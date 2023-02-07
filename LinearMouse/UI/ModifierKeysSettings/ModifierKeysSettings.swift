// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ModifierKeysSettings: View {
    @ObservedObject var state: ModifierKeysSettingsState = .shared

    var body: some View {
        DetailView {
            Form {
                Section {
                    ModifierKeyActionPicker(label: "⌘ (Command)", action: $state.commandAction)
                    ModifierKeyActionPicker(label: "⇧ (Shift)", action: $state.shiftAction)
                    ModifierKeyActionPicker(label: "⌥ (Option)", action: $state.optionAction)
                    ModifierKeyActionPicker(label: "⌃ (Control)", action: $state.controlAction)
                }
                .modifier(SectionViewModifier())
            }
            .modifier(FormViewModifier())
        }
    }
}
