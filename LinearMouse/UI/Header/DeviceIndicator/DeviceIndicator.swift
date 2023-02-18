// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct DeviceIndicator: View {
    @ObservedObject private var state = DeviceIndicatorState.shared
    @State private var showDevicePickerSheet = false

    var body: some View {
        Button(action: { showDevicePickerSheet.toggle() }) {
            Text(state.activeDeviceName ?? "Unknown")
                .frame(maxWidth: 150)
                .fixedSize()
                .lineLimit(1)
        }
        .controlSize(.small)
        .buttonStyle(SecondaryButtonStyle())
        .sheet(isPresented: $showDevicePickerSheet) {
            DevicePickerSheet()
                .environment(\.isPresented, $showDevicePickerSheet)
        }
    }
}
