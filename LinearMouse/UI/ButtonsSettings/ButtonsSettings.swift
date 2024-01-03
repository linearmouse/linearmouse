// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct ButtonsSettings: View {
    var body: some View {
        DetailView {
            Form {
                UniversalBackForwardSection()

                SwitchPrimaryAndSecondaryButtonsSection()

                ClickDebouncingSection()

                ButtonMappingsSection()
            }
            .modifier(FormViewModifier())
        }
    }
}
