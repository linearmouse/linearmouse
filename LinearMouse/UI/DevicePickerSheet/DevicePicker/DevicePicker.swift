// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DevicePicker: View {
    @StateObject var model = DevicePickerModel()

    var body: some View {
        List {
            DevicePickerSection(title: "Mouse", devices: model.devices.filter(\.isMouse))
            DevicePickerSection(title: "Trackpad", devices: model.devices.filter(\.isTrackpad))
        }
        .frame(minWidth: 350)
    }
}

struct DevicePicker_Previews: PreviewProvider {
    static var previews: some View {
        DevicePicker()
    }
}
