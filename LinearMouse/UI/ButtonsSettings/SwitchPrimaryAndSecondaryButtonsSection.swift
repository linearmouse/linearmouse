// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct SwitchPrimaryAndSecondaryButtonsSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.switchPrimaryAndSecondaryButtons) {
                Text("Switch primary and secondary buttons")
            }
        }
        .modifier(SectionViewModifier())
    }
}
