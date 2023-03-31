// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ControlClickSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.controlClickDisabled.animation()) {
                withDescription {
                    Text("Disable control click")
                    Text("Left clicking with control will not be changed to a right click")
                }
            }
        }
    }
}
