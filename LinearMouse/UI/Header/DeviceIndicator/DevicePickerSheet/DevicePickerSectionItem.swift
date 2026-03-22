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

                        if let batteryLevel = deviceModel.batteryLevel,
                           deviceModel.pairedReceiverDevices.isEmpty {
                            BatteryLevelIndicator(level: batteryLevel)
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
                                    BatteryLevelIndicator(level: batteryLevel, compact: true)
                                }
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
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
                minHeight: deviceModel.pairedReceiverDevices.isEmpty ? 38 : 58,
                alignment: .leading
            )
            .animation(
                .spring(response: 0.26, dampingFraction: 0.88),
                value: deviceModel.pairedReceiverDevices.map(\.slot)
            )
        }
        .buttonStyle(DeviceButtonStyle(isSelected: isSelected))
    }
}

private struct BatteryLevelIndicator: View {
    let level: Int
    var compact = false

    private var clampedLevel: Int {
        min(max(level, 0), 100)
    }

    private var tintColor: Color {
        switch clampedLevel {
        case ..<16:
            return .red
        case ..<36:
            return .orange
        default:
            return .green
        }
    }

    private var bodyWidth: CGFloat {
        compact ? 18 : 22
    }

    private var bodyHeight: CGFloat {
        compact ? 9 : 11
    }

    private var fillWidth: CGFloat {
        let usableWidth = bodyWidth - 4
        let proportionalWidth = usableWidth * CGFloat(clampedLevel) / 100
        return max(clampedLevel == 0 ? 0 : 2, proportionalWidth)
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            HStack(spacing: compact ? 3 : 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: bodyHeight / 3)
                        .fill(Color.primary.opacity(0.05))

                    RoundedRectangle(cornerRadius: bodyHeight / 3)
                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)

                    if fillWidth > 0 {
                        RoundedRectangle(cornerRadius: (bodyHeight - 4) / 3)
                            .fill(
                                LinearGradient(
                                    colors: [tintColor.opacity(0.95), tintColor.opacity(0.68)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth, height: bodyHeight - 4)
                            .padding(2)
                    }
                }
                .frame(width: bodyWidth, height: bodyHeight)

                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: compact ? 2 : 2.5, height: bodyHeight * 0.42)
            }

            Text("\(clampedLevel)%")
                .font(compact ? .caption : .callout)
                .foregroundColor(.secondary)
                .font(.system(size: compact ? 11 : 12, weight: .regular, design: .monospaced))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("Battery \(clampedLevel) percent"))
    }
}
