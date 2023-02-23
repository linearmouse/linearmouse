// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonsSettings: View {
    var body: some View {
        DetailView {
            Form {
                UniversalBackForwardSection()

                ClickDebouncingSection()
            }
            .modifier(FormViewModifier())
        }
    }
}
