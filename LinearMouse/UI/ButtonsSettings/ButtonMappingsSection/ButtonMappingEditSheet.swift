// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingEditSheet: View {
    @Binding var isPresented: Bool

    @ObservedObject private var state: ButtonsSettingsState = .shared

    @Binding var mapping: Scheme.Buttons.Mapping
    let completion: ((Scheme.Buttons.Mapping) -> Void)?

    @State private var mode: Mode

    init(
        isPresented: Binding<Bool>,
        mapping: Binding<Scheme.Buttons.Mapping>,
        mode: Mode = .edit,
        completion: ((Scheme.Buttons.Mapping) -> Void)?
    ) {
        _isPresented = isPresented
        _mapping = mapping
        self.completion = completion
        self.mode = mode
    }

    var body: some View {
        VStack(spacing: 20) {
            Form {
                Group {
                    if mode == .edit {
                        ButtonMappingButtonDescription<EmptyView>(mapping: mapping)
                    } else {
                        ButtonMappingButtonRecorder(
                            mapping: $mapping,
                            autoStartRecording: mode == .create
                        )
                    }
                }
                .formLabel(Text("Trigger"))

                if !valid, conflicted {
                    Text("The trigger is already assigned.")
                        .foregroundColor(.red)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !valid, mapping.button?.mouseButtonNumber == 0, mapping.modifierFlags.isEmpty {
                    Text("Assigning an action to the left button without any modifier keys is not allowed.")
                        .foregroundColor(.red)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if valid {
                    ButtonMappingAction(action: $mapping.action.default(.arg0(.auto)))

                    if mapping.button != nil {
                        if mapping.isKeyPressAction {
                            Picker("While pressed", selection: $mapping.keyPressBehavior) {
                                Text("Send once on release").tag(Scheme.Buttons.Mapping.KeyPressBehavior.sendOnRelease)
                                Text("Repeat").tag(Scheme.Buttons.Mapping.KeyPressBehavior.repeat)
                                Text("Hold keys while pressed").tag(
                                    Scheme.Buttons.Mapping.KeyPressBehavior.holdWhilePressed
                                )
                            }
                            .modifier(PickerViewModifier())
                        } else {
                            Toggle(isOn: $mapping.repeat.default(false)) {
                                Text("Repeat on hold")
                            }
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

private extension Scheme.Buttons.Mapping {
    var isKeyPressAction: Bool {
        guard case .arg1(.keyPress) = action else {
            return false
        }

        return true
    }
}

private extension Binding where Value == Scheme.Buttons.Mapping {
    var keyPressBehavior: Binding<Scheme.Buttons.Mapping.KeyPressBehavior> {
        Binding<Scheme.Buttons.Mapping.KeyPressBehavior>(
            get: {
                wrappedValue.keyPressBehavior
            },
            set: {
                wrappedValue.keyPressBehavior = $0
            }
        )
    }
}
