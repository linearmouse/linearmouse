// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct RequireTwoFingerScrollSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Toggle(isOn: $state.requireTwoFingerScroll) {
                    withDescription {
                        Text("Require two fingers to scroll")
                        Text("Matches trackpad behavior: scrolling only starts once two fingers are on the surface, instead of on any single finger contact.")
                    }
                }
            }
            .modifier(SectionViewModifier())
        }
    }
}
