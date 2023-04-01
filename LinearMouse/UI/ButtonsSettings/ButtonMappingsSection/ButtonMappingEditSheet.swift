// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingEditSheet: View {
    @Environment(\.isPresented) var isPresented

    @ObservedObject private var state: ButtonsSettingsState = .shared

    @Binding var mapping: Scheme.Buttons.Mapping
    var mode: Mode = .edit
    var completion: ((Scheme.Buttons.Mapping) -> Void)?

    var body: some View {
        VStack {
            Form {
                Group {
                    if mode == .edit {
                        ButtonMappingButtonDescription<EmptyView>(mapping: mapping)
                    } else {
                        ButtonMappingButtonRecorder(mapping: $mapping, autoStartRecording: mode == .create)
                    }
                }
                .formLabel(Text("Mouse button"))

                if !valid, conflicted {
                    Text("The mouse button already exists.")
                        .foregroundColor(.red)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !valid, mapping.button == 0, mapping.modifierFlags.isEmpty {
                    Text("Assigning an action to the left button without any modifier keys is not allowed.")
                        .foregroundColor(.red)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ButtonMappingActionPicker(action: $mapping.action.default(.simpleAction(.auto)))
            }

            Button("OK") {
                isPresented?.wrappedValue.toggle()
                completion?(mapping)
            }
            .disabled(!valid)
        }
        .padding()
        .frame(width: 400)
    }
}

extension ButtonMappingEditSheet {
    enum Mode {
        case edit, create
    }

    var conflicted: Bool {
        !state.mappings.allSatisfy { !mapping.conflicted(with: $0) }
    }

    var valid: Bool {
        guard mapping.valid else {
            return false
        }

        guard mode == .edit || !conflicted else {
            return false
        }

        return true
    }
}
