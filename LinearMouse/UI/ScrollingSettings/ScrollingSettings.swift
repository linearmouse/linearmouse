// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ScrollingSettings: View {
    @ObservedObject private var state = ScrollingSettingsState.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading) {
                Header()

                Form {
                    ReverseScrollingSection()

                    if state.showsHighResolutionWheelControl {
                        LogitechHighResolutionWheelSection()
                    }

                    ScrollingModeSection()

                    ModifierKeysSection()
                }
                .modifier(FormViewModifier())
            }
        }
        .onAppear {
            state.refreshHighResolutionWheelInfo()
        }
    }
}
