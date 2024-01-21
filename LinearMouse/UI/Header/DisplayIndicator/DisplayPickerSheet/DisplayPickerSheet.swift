// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct DisplayPickerSheet: View {
    @Binding var isPresented: Bool
    @State var selectedDisplay = ""

    private let schemeState: SchemeState = .shared

    var body: some View {
        VStack(spacing: 8) {
            Form {
                DisplayPicker(selectedDisplay: $selectedDisplay)
            }
            .modifier(FormViewModifier())

            HStack {
                Spacer()
                Button("OK", action: onOK)
            }
            .padding()
        }
        .frame(minWidth: 300)
        .onAppear {
            selectedDisplay = schemeState.currentDisplay ?? ""
        }
    }

    private func onOK() {
        isPresented = false
        DispatchQueue.main.async {
            schemeState.currentDisplay = selectedDisplay == "" ? nil : selectedDisplay
        }
    }
}
