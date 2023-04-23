// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct DevicePickerSectionItem: View {
    @ObservedObject var deviceModel: DeviceModel
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(deviceModel.name)

                if deviceModel.isActive {
                    Text("(active)")
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                }
            }
            .transition(.move(edge: .leading))
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(DeviceButtonStyle(isSelected: deviceModel.isSelected))
    }
}
