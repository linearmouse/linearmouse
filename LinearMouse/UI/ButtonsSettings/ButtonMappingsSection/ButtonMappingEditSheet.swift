// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct ButtonMappingEditSheet: View {
    @Binding var isPresented: Bool

    @ObservedObject private var state: ButtonsSettingsState = .shared

    @Binding var mapping: Scheme.Buttons.Mapping
    @State private var mode: Mode = .edit
    let completion: ((Scheme.Buttons.Mapping) -> Void)?

    var body: some View {
        VStack(spacing: 20) {
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
                    Text("The mouse button is already assigned.")
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

                if valid {
                    ButtonMappingAction(action: $mapping.action.default(.arg0(.auto)))

                    if mapping.button != nil {
                        Toggle(isOn: $mapping.repeat.default(false)) {
                            Text("Repeat on hold")
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }

                Button(mode == .create ? "Create" : "OK") {
                    isPresented = false
                    mode = .edit
                    completion?(mapping)
                }
                .disabled(!valid)
                .asDefaultAction()
            }
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
        guard mode == .create else {
            return false
        }

        return !state.mappings.allSatisfy { !mapping.conflicted(with: $0) }
    }

    var valid: Bool {
        mapping.valid && !conflicted
    }
}
