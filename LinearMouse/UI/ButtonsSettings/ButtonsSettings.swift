// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct ButtonsSettings: View {
    var body: some View {
        DetailView {
            Form {
                UniversalBackForwardSection()

                ClickDebouncingSection()

                ButtonMappingsSection()
            }
            .modifier(FormViewModifier())
        }
    }
}
