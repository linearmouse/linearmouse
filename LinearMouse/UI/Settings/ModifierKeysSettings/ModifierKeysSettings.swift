// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct ModifierKeysSettings: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        DetailView {
            Form {
                ModifierKeyActionPicker(label: "⌘ (Command)", action: $defaults.modifiersCommandAction)

                ModifierKeyActionPicker(label: "⇧ (Shift)", action: $defaults.modifiersShiftAction)

                ModifierKeyActionPicker(label: "⌥ (Option)", action: $defaults.modifiersAlternateAction)

                ModifierKeyActionPicker(label: "⌃ (Control)", action: $defaults.modifiersControlAction)
            }
        }
    }
}

struct ModifierKeysSettings_Previews: PreviewProvider {
    static var previews: some View {
        ModifierKeysSettings()
    }
}
