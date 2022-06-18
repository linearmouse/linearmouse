// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DevicePickerSection: View {
    var title: LocalizedStringKey
    var devices: [DeviceModel]
    @Environment(\.isPresented) var isPresented

    @StateObject var model = DevicePickerSectionModel()

    var body: some View {
        Section(header: Text(title)) {
            ForEach(devices) { deviceModel in
                DevicePickerSectionItem(deviceModel: deviceModel) {
                    model.setDevice(deviceModel)
                    isPresented?.wrappedValue = false
                }
            }
        }
    }
}

struct DevicePickerSection_Previews: PreviewProvider {
    static var previews: some View {
        DevicePickerSection(title: "Mouse",
                            devices: DevicePickerModel().devices)
    }
}
