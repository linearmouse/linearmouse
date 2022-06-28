// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DevicePicker: View {
    @StateObject var state = DevicePickerState()

    var body: some View {
        List {
            DevicePickerSection(title: "Mouse", devices: state.devices.filter(\.isMouse))
            DevicePickerSection(title: "Trackpad", devices: state.devices.filter(\.isTrackpad))
        }
        .frame(minWidth: 350)
    }
}

struct DevicePicker_Previews: PreviewProvider {
    static var previews: some View {
        DevicePicker()
    }
}
