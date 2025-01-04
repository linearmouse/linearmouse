// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct UniversalBackForwardSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.universalBackForward) {
                withDescription {
                    Text("Enable universal back and forward")
                    Text(
                        "Convert the back and forward side buttons to swiping gestures to allow universal back and forward functionality."
                    )
                }
            }
        }
        .modifier(SectionViewModifier())
    }
}
