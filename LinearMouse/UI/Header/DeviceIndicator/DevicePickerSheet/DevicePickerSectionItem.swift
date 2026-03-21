// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DevicePickerSectionItem: View {
    @ObservedObject var deviceModel: DeviceModel
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(deviceModel.pairedReceiverDevices.isEmpty ? deviceModel.displayName : deviceModel.name)
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

                if !deviceModel.pairedReceiverDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(deviceModel.pairedReceiverDevices, id: \.slot) { device in
                            HStack(spacing: 6) {
                                Text(String(format: NSLocalizedString("- %@", comment: ""), device.name))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                if let batteryLevel = device.batteryLevel {
                                    Text("\(batteryLevel)%")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.leading, 12)
                }
            }
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal: .opacity
                )
            )
            .frame(
                maxWidth: .infinity,
                minHeight: deviceModel.pairedReceiverDevices.isEmpty ? 34 : 52,
                alignment: .leading
            )
        }
        .buttonStyle(DeviceButtonStyle(isSelected: isSelected))
    }
}
