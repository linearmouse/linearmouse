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
            ForEach(devices) { device in
                Button(action: {
                    model.setDevice(device)
                    isPresented?.wrappedValue = false
                }) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(device.name)

                        if device.isActive {
                            Text("(active)")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(DeviceButtonStyle(isSelected: device.isSelected))
                .transition(.opacity)
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
