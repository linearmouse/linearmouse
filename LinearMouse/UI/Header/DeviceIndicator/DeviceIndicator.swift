// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DeviceIndicator: View {
    @StateObject private var state = DeviceIndicatorState()
    @State private var showDevicePickerSheet = false

    var body: some View {
        Button(action: handleClick) {
            Text(state.activeDeviceName ?? "Unknown")
                .frame(maxWidth: 150)
                .fixedSize()
                .lineLimit(1)
        }
        .buttonStyle(SecondaryButtonStyle())
        .sheet(isPresented: $showDevicePickerSheet) {
            DevicePickerSheet()
                .environment(\.isPresented, $showDevicePickerSheet)
        }
    }

    private func handleClick() {
        showDevicePickerSheet.toggle()
    }
}

struct DeviceIndicator_Previews: PreviewProvider {
    static var previews: some View {
        DeviceIndicator()
    }
}
