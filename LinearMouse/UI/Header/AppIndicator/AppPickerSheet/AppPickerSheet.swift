// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct AppPickerSheet: View {
    @Binding var isPresented: Bool
    @State var selectedApp = ""

    private let schemeState: SchemeState = .shared

    var body: some View {
        VStack(spacing: 8) {
            Form {
                AppPicker(selectedApp: $selectedApp)
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
            selectedApp = schemeState.currentApp ?? ""
        }
    }

    private func onOK() {
        isPresented = false
        DispatchQueue.main.async {
            schemeState.currentApp = selectedApp == "" ? nil : selectedApp
        }
    }
}
