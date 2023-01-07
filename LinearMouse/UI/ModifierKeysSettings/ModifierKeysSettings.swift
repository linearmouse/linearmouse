// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ModifierKeysSettings: View {
    @StateObject var state = ModifierKeysSettingsState()

    var body: some View {
        DetailView {
            Form {
                ModifierKeyActionPicker(label: "⌘ (Command)", action: $state.commandAction)

                ModifierKeyActionPicker(label: "⇧ (Shift)", action: $state.shiftAction)

                ModifierKeyActionPicker(label: "⌥ (Option)", action: $state.optionAction)

                ModifierKeyActionPicker(label: "⌃ (Control)", action: $state.controlAction)
            }
        }
    }
}
