// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonsSettings: View {
    var body: some View {
        DetailView {
            Form {
                UniversalBackForwardSection()

                SwitchPrimaryAndSecondaryButtonsSection()

                ClickDebouncingSection()

                GestureButtonSection()

                ButtonMappingsSection()
            }
            .modifier(FormViewModifier())
        }
    }
}
