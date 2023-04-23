// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct DevicePickerSection: View {
    var title: LocalizedStringKey
    var devices: [DeviceModel]
    @Environment(\.isPresented) var isPresented

    @ObservedObject var state = DevicePickerSectionState.shared

    var body: some View {
        Section(header: Text(title)) {
            ForEach(devices) { deviceModel in
                DevicePickerSectionItem(deviceModel: deviceModel) {
                    state.setDevice(deviceModel)
                    isPresented?.wrappedValue = false
                }
            }
        }
    }
}
