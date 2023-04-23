// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct DevicePicker: View {
    @ObservedObject var state = DevicePickerState.shared

    var body: some View {
        List {
            DevicePickerSection(title: "Mouse", devices: state.devices.filter(\.isMouse))
            DevicePickerSection(title: "Trackpad", devices: state.devices.filter(\.isTrackpad))
        }
        .frame(minWidth: 350)
    }
}
