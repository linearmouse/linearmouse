// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct ButtonMappingsSection: View {
    @ObservedObject private var state: ButtonsSettingsState = .shared

    @State private var selection: Set<Scheme.Buttons.Mapping> = []

    @State private var showAddSheet = false
    @State private var mappingToAdd: Scheme.Buttons.Mapping = .init()

    var body: some View {
        Section {
            if #available(macOS 13.0, *) {
                if !state.mappings.isEmpty {
                    List($state.mappings, id: \.self, selection: $selection) { $mapping in
                        ButtonMappingListItem(mapping: $mapping)
                    }
                }
            } else {
                List($state.mappings, id: \.self, selection: $selection) { $mapping in
                    ButtonMappingListItem(mapping: $mapping)
                }
                .frame(height: 200)
            }
        } header: {
            Text("Assign actions to mouse buttons")
        } footer: {
            HStack(spacing: 4) {
                Button {
                    mappingToAdd = .init()
                    showAddSheet.toggle()
                } label: {
                    VStack {
                        Image("Plus")
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showAddSheet) {
                    ButtonMappingEditSheet(
                        isPresented: $showAddSheet,
                        mapping: $mappingToAdd,
                        mode: .create
                    ) { mapping in
                        state.appendMapping(mapping)
                    }
                }

                Button {
                    state.mappings = state.mappings.filter { !selection.contains($0) }
                    selection = []
                } label: {
                    VStack {
                        Image("Minus")
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(selection.isEmpty)
            }
        }
        .modifier(SectionViewModifier())
    }
}
