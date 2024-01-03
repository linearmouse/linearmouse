// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct ScrollingSettings: View {
    var body: some View {
        DetailView {
            VStack(alignment: .leading) {
                Header()

                Form {
                    ReverseScrollingSection()

                    ScrollingModeSection()

                    ModifierKeysSection()
                }
                .modifier(FormViewModifier())
            }
        }
    }
}
