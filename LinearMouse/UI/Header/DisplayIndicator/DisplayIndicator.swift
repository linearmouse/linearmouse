// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct DisplayIndicator: View {
    @State private var showDisplayPickerSheet = false

    @ObservedObject private var schemeState: SchemeState = .shared

    var body: some View {
        Button {
            showDisplayPickerSheet.toggle()
        } label: {
            Text(schemeState.currentDisplay ?? NSLocalizedString("All Displays", comment: ""))
                .frame(maxWidth: 150)
                .fixedSize()
                .lineLimit(1)
        }
        .controlSize(.small)
        .buttonStyle(SecondaryButtonStyle())
        .sheet(isPresented: $showDisplayPickerSheet) {
            DisplayPickerSheet(isPresented: $showDisplayPickerSheet)
        }
    }
}
