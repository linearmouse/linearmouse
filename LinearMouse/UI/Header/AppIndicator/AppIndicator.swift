// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct AppIndicator: View {
    @State private var showAppPickerSheet = false

    @ObservedObject private var schemeState: SchemeState = .shared

    var body: some View {
        Button(action: { showAppPickerSheet.toggle() }) {
            Text(schemeState.currentApp ?? NSLocalizedString("All Apps", comment: ""))
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
