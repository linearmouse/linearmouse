// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct DevicePicker: View {
    @ObservedObject var state = DevicePickerState.shared

    @Binding var isPresented: Bool

    var body: some View {
        List {
            DevicePickerSection(
                isPresented: $isPresented, title: "Mouse",
                devices: state.devices.filter(\.isMouse)
            )
            DevicePickerSection(
                isPresented: $isPresented,
                title: "Trackpad",
                devices: state.devices.filter(\.isTrackpad)
            )
        }
        .frame(minWidth: 350)
    }
}
