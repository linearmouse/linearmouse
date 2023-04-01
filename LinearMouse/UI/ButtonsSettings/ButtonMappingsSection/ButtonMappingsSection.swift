// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingsSection: View {
    @ObservedObject private var state: ButtonsSettingsState = .shared

    @State private var selection: Set<Scheme.Buttons.Mapping> = []

    @State private var showAddSheet = false
    @State private var mappingToAdd: Scheme.Buttons.Mapping = .init()

    var body: some View {
        Section {
            Text("Assign actions to mouse buttons.")

            if !state.mappings.isEmpty {
                List($state.mappings, id: \.self, selection: $selection) { $mapping in
                    ButtonMappingListItem(mapping: $mapping)
                }
            }
        } footer: {
            HStack(spacing: 4) {
                Button(action: {
                    mappingToAdd = .init()
                    showAddSheet.toggle()
                }) {
                    Image("Plus")
                }
                .sheet(isPresented: $showAddSheet) {
                    ButtonMappingEditSheet(mapping: $mappingToAdd, mode: .create) { mapping in
                        state.appendMapping(mapping)
                    }
                    .environment(\.isPresented, $showAddSheet)
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
