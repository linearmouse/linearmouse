// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct AppPickerSheet: View {
    @Binding var isPresented: Bool
    @State private var selectedApp = ""

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
            switch schemeState.currentApp {
            case .none:
                selectedApp = ""
            case let .bundle(bundleIdentifier):
                selectedApp = bundleIdentifier
            case let .executable(path):
                selectedApp = "executable:\(path)"
            }
        }
    }

    private func onOK() {
        isPresented = false
        DispatchQueue.main.async {
            if selectedApp.hasPrefix("executable:") {
                let path = String(selectedApp.dropFirst("executable:".count))
                schemeState.currentApp = .executable(path)
            } else if selectedApp.isEmpty {
                schemeState.currentApp = nil
            } else {
                schemeState.currentApp = .bundle(selectedApp)
            }
        }
    }
}
