// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DevicePicker: View {
    @ObservedObject var state = DevicePickerState.shared

    @Binding var selectedDeviceRef: WeakRef<Device>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DevicePickerSection(
                    selectedDeviceRef: $selectedDeviceRef, title: "Mouse",
                    devices: state.devices.filter(\.isMouse)
                )
                DevicePickerSection(
                    selectedDeviceRef: $selectedDeviceRef,
                    title: "Trackpad",
                    devices: state.devices.filter(\.isTrackpad)
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 350)
    }
}
