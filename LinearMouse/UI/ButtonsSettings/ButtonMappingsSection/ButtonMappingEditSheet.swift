// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingEditSheet: View {
    @Environment(\.isPresented) var isPresented

    @Binding var mapping: Scheme.Buttons.Mapping
    var autoStartRecording = false
    var completion: ((Scheme.Buttons.Mapping) -> Void)?

    var body: some View {
        VStack {
            Form {
                ButtonMappingButtonRecorder(mapping: $mapping, autoStartRecording: autoStartRecording)
                    .formLabel(Text("Mouse button"))

                ButtonMappingActionPicker(action: $mapping.action.default(.simpleAction(.auto)))

                if !mapping.isValid, mapping.button == 0, mapping.modifierFlags.isEmpty {
                    Text("Assigning an action to the left button without any modifier keys is not allowed.")
                        .foregroundColor(.red)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("OK") {
                isPresented?.wrappedValue.toggle()
                completion?(mapping)
            }
            .disabled(!mapping.isValid)
        }
        .padding()
        .frame(width: 400)
    }
}
