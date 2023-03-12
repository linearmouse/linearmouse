// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingsSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared
    @State var selection: Set<Scheme.Buttons.Mapping> = []

    var body: some View {
        Section {
            List($state.mappings, id: \.self, selection: $selection) { $mapping in
                ButtonMapping(mapping: $mapping).tag(mapping)
            }
        }
        .modifier(SectionViewModifier())
    }
}
