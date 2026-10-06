// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ClickThroughSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.clickThrough) {
                withDescription {
                    Text("Click through to inactive windows")
                    Text(
                        "Clicking a window of an inactive app also clicks the item under the pointer, instead of only activating the app."
                    )
                }
            }
        }
        .modifier(SectionViewModifier())
    }
}
