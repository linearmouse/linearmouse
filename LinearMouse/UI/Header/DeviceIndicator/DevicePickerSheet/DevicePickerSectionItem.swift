// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DevicePickerSectionItem: View {
    @ObservedObject var deviceModel: DeviceModel
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(deviceModel.name)
                        .font(.body)

                    if let batteryDescription = deviceModel.batteryDescription {
                        Text(batteryDescription)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    if deviceModel.isActive {
                        Text("(active)")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected, #available(macOS 11.0, *) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal: .opacity
                )
            )
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(DeviceButtonStyle(isSelected: isSelected))
    }
}
