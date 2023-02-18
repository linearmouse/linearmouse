// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct AppPickerSheet: View {
    @Environment(\.isPresented) var isPresented
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
        schemeState.currentApp = selectedApp == "" ? nil : selectedApp
        isPresented?.wrappedValue.toggle()
    }
}

struct AppPickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        AppPickerSheet()
    }
}
