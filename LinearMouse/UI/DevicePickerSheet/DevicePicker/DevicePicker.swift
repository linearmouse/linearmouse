//
//  DevicePicker.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/17.
//

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
