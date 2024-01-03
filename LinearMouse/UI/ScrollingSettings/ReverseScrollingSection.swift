// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ReverseScrollingSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Toggle(isOn: $state.reverseScrolling) {
                    withDescription {
                        Text("Reverse scrolling")
                        if state.direction == .horizontal {
                            Text("Some gestures, such as swiping back and forward, may stop working.")
                        }
                    }
                }
            }
            .modifier(SectionViewModifier())
        }
    }
}
