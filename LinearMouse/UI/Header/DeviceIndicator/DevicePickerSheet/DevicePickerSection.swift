// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct DevicePickerSection: View {
    @Binding var isPresented: Bool

    var title: LocalizedStringKey
    var devices: [DeviceModel]

    @ObservedObject var state = DevicePickerSectionState.shared

    var body: some View {
        Section(header: Text(title)) {
            ForEach(devices) { deviceModel in
                DevicePickerSectionItem(deviceModel: deviceModel) {
                    state.setDevice(deviceModel)
                    isPresented = false
                }
            }
        }
    }
}
