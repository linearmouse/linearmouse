// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct AppIndicator: View {
    @State private var showAppPickerSheet = false

    @ObservedObject private var schemeState: SchemeState = .shared

    var body: some View {
        Button {
            showAppPickerSheet.toggle()
        } label: {
            Text(schemeState.currentAppName ?? NSLocalizedString("All Apps", comment: ""))
                .frame(maxWidth: 150)
                .fixedSize()
                .lineLimit(1)
        }
        .controlSize(.small)
        .buttonStyle(SecondaryButtonStyle())
        .sheet(isPresented: $showAppPickerSheet) {
            AppPickerSheet()
                .environment(\.isPresented, $showAppPickerSheet)
        }
    }
}
