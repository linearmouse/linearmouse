// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct DeviceIndicator: View {
    @ObservedObject private var state = DeviceIndicatorState.shared
    @State private var showDevicePickerSheet = false

    var body: some View {
        Button {
            showDevicePickerSheet.toggle()
        } label: {
            Text(state.activeDeviceName ?? "Unknown")
                .frame(maxWidth: 150)
                .fixedSize()
                .lineLimit(1)
        }
        .controlSize(.small)
        .buttonStyle(SecondaryButtonStyle())
        .sheet(isPresented: $showDevicePickerSheet) {
            DevicePickerSheet(isPresented: $showDevicePickerSheet)
        }
    }
}
