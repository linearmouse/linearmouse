// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct ConfigurationSection: View {
    @ObservedObject var configurationState = ConfigurationState.shared

    var body: some View {
        Section {
            HStack {
                Button("Reload Config") {
                    configurationState.load()
                }
                .disabled(configurationState.loading)

                Button("Reveal Config in Finder…") {
                    configurationState.revealInFinder()
                }
            }
        }
        .modifier(SectionViewModifier())
    }
}
