// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DeviceIndicator: View {
    @StateObject private var model = DeviceIndicatorModel()
    @State private var showDevicePickerSheet = false

    var body: some View {
        Button(action: handleClick) {
            Text(model.activeDeviceName ?? "Unknown")
                .frame(maxWidth: 150)
                .fixedSize()
                .lineLimit(1)
        }
        .buttonStyle(SecondaryButtonStyle())
        .sheet(isPresented: $showDevicePickerSheet) {
            DevicePickerSheet()
                .controlSize(.regular)
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
