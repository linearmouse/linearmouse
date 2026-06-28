// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingsSection: View {
    @ObservedObject private var state: ButtonsSettingsState = .shared

    @State private var selection: Set<Scheme.Buttons.Mapping> = []

    @State private var activeSheet: ActiveSheet?
    @State private var mappingDraft: Scheme.Buttons.Mapping = .init()
    @State private var editingOriginalMapping: Scheme.Buttons.Mapping?

    var body: some View {
        Section {
            if #available(macOS 13.0, *) {
                if !state.mappings.isEmpty {
                    List($state.mappings, id: \.self, selection: $selection) { $mapping in
                        ButtonMappingListItem(mapping: $mapping, onEdit: beginEditing)
                    }
                }
            } else {
                List($state.mappings, id: \.self, selection: $selection) { $mapping in
                    ButtonMappingListItem(mapping: $mapping, onEdit: beginEditing)
                }
                .frame(height: 200)
            }
        } header: {
            Text("Assign actions to mouse buttons")
        } footer: {
            HStack(spacing: 4) {
                Button {
                    beginAdding()
                } label: {
                    VStack {
                        Image("Plus")
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

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
        .sheet(item: $activeSheet) { sheet in
            ButtonMappingEditSheet(
                isPresented: sheetPresented,
                mapping: $mappingDraft,
                mode: sheet.mode
            ) { mapping in
                apply(mapping, from: sheet)
            }
        }
    }

    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { activeSheet != nil },
            set: { isPresented in
                if !isPresented {
                    activeSheet = nil
                    editingOriginalMapping = nil
                }
            }
        )
    }

    private func beginAdding() {
        mappingDraft = .init()
        editingOriginalMapping = nil
        activeSheet = .create
    }

    private func beginEditing(_ mapping: Scheme.Buttons.Mapping) {
        mappingDraft = mapping
        editingOriginalMapping = mapping
        activeSheet = .edit
    }

    private func apply(_ mapping: Scheme.Buttons.Mapping, from sheet: ActiveSheet) {
        switch sheet {
        case .create:
            state.appendMapping(mapping)

        case .edit:
            guard let editingOriginalMapping,
                  let index = state.mappings.firstIndex(of: editingOriginalMapping) else {
                return
            }
            state.mappings[index] = mapping
        }
    }
}

private extension ButtonMappingsSection {
    enum ActiveSheet: String, Identifiable {
        case create
        case edit

        var id: String {
            rawValue
        }

        var mode: ButtonMappingEditSheet.Mode {
            switch self {
            case .create:
                return .create
            case .edit:
                return .edit
            }
        }
    }
}
