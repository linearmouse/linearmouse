// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingEditSheet: View {
    @Environment(\.isPresented) var isPresented

    @Binding var mapping: Scheme.Buttons.Mapping
    var completion: ((Scheme.Buttons.Mapping) -> Void)?

    var body: some View {
        VStack {
            Form {
                ButtonMappingButtonRecorder(mapping: $mapping)
                    .formLabel(Text("Mouse button"))

                ButtonMappingActionPicker(action: $mapping.action.default(.simpleAction(.auto)))
            }

            Button("OK") {
                isPresented?.wrappedValue.toggle()
                completion?(mapping)
            }
            .disabled(!mapping.isValid)
        }
        .padding()
        .frame(width: 320)
    }
}
