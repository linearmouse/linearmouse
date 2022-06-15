// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct ModifierKeysView: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        ScrollView {
            Form {
                ModifierKeyActionPicker(label: "⌘ (Command)", action: $defaults.modifiersCommandAction)

                ModifierKeyActionPicker(label: "⇧ (Shift)", action: $defaults.modifiersShiftAction)

                ModifierKeyActionPicker(label: "⌥ (Option)", action: $defaults.modifiersAlternateAction)

                ModifierKeyActionPicker(label: "⌃ (Control)", action: $defaults.modifiersControlAction)
            }
        }
        .padding(40)
        .frame(minWidth: 500,
               maxWidth: .infinity,
               alignment: .topLeading)
    }
}

struct ModifierKeysView_Previews: PreviewProvider {
    static var previews: some View {
        ModifierKeysView()
    }
}
