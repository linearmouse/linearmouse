// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingEditSheet: View {
    @Environment(\.isPresented) var isPresented

    @Binding var mapping: Scheme.Buttons.Mapping

    var body: some View {
        VStack {
            Form {
                ButtonMappingButtonRecorder(mapping: $mapping)
                    .formLabel(Text("Mouse button"))

                Picker("Action", selection: .constant(0)) {}
            }

            Button("OK") {
                isPresented?.wrappedValue.toggle()
            }
        }
        .padding()
        .frame(width: 320)
    }
}
