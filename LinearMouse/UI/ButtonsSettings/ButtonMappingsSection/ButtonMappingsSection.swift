// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingsSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared
    @State var selection: Set<Scheme.Buttons.Mapping> = []

    var body: some View {
        Section {
            Text("Assign actions to mouse buttons.")

            List($state.mappings, id: \.self, selection: $selection) { $mapping in
                ButtonMapping(mapping: $mapping)
            }
        } footer: {
            HStack(spacing: 4) {
                Button(action: {}) {
                    Image("Plus")
                }

                Button(action: {
                    state.mappings = state.mappings.filter { !selection.contains($0) }
                    selection = []
                }) {
                    Image("Minus")
                }
                .disabled(selection.count == 0)
            }
        }
        .modifier(SectionViewModifier())
    }
}
