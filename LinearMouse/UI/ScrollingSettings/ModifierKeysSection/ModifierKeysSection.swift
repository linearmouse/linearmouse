// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ModifierKeysSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section(header: Text("Modifier Keys")) {
                ModifierKeyActionPicker(label: "⌘ (Command)", action: $state.modifiers.command)
                ModifierKeyActionPicker(label: "⇧ (Shift)", action: $state.modifiers.shift)
                ModifierKeyActionPicker(label: "⌥ (Option)", action: $state.modifiers.option)
                ModifierKeyActionPicker(label: "⌃ (Control)", action: $state.modifiers.control)
            }
            .modifier(SectionViewModifier())
        }
    }
}
