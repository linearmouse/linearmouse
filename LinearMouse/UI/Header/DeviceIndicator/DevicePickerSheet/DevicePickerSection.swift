// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DevicePickerSection: View {
    @Binding var selectedDeviceRef: WeakRef<Device>?

    var title: LocalizedStringKey
    var devices: [DeviceModel]
    var onSelectDevice: (WeakRef<Device>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(devices) { deviceModel in
                    DevicePickerSectionItem(
                        deviceModel: deviceModel,
                        isSelected: isSelected(deviceModel)
                    ) {
                        selectedDeviceRef = deviceModel.deviceRef
                        onSelectDevice(deviceModel.deviceRef)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSelected(_ deviceModel: DeviceModel) -> Bool {
        guard let selectedDevice = selectedDeviceRef?.value else {
            return false
        }

        return deviceModel.deviceRef.value === selectedDevice
    }
}
