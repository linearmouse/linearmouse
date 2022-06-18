//
//  DevicePickerSection.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/18.
//

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
                    Text(device.name)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(DeviceButtonStyle(isActive: device.isActive))
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
