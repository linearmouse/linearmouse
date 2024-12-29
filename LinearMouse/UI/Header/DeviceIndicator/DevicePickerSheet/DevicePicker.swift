// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct DevicePicker: View {
    @ObservedObject var state = DevicePickerState.shared

    @Binding var isPresented: Bool

    var body: some View {
        List {
            DevicePickerSection(
                isPresented: $isPresented, title: "Mouse",
                devices: state.devices.filter(\.isMouse))
            DevicePickerSection(
                isPresented: $isPresented,
                title: "Trackpad",
                devices: state.devices.filter(\.isTrackpad)
            )
            DevicePickerSection(
                isPresented: $isPresented,
                title: "Trackball",
                devices: state.devices.filter(\.isTrackball)
            )
        }
        .frame(minWidth: 350)
    }
}
