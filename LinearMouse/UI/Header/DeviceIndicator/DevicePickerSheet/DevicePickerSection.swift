// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DevicePickerSection: View {
    @Binding var selection: DevicePickerSelection?

    var category: DeviceMatcher.Category
    var title: LocalizedStringKey
    var devices: [DeviceModel]
    var onSelectCategory: (DeviceMatcher.Category) -> Void
    var onSelectDevice: (WeakRef<Device>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                DevicePickerCategoryItem(
                    category: category,
                    isSelected: isCategorySelected
                ) {
                    selection = .category(category)
                    onSelectCategory(category)
                }

                ForEach(devices) { deviceModel in
                    DevicePickerSectionItem(
                        deviceModel: deviceModel,
                        isSelected: isSelected(deviceModel)
                    ) {
                        selection = .device(deviceModel.deviceRef)
                        onSelectDevice(deviceModel.deviceRef)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCategorySelected: Bool {
        guard case let .category(selectedCategory) = selection else {
            return false
        }

        return selectedCategory == category
    }

    private func isSelected(_ deviceModel: DeviceModel) -> Bool {
        guard case let .device(selectedDeviceRef) = selection,
              let selectedDevice = selectedDeviceRef.value else {
            return false
        }

        return deviceModel.deviceRef.value === selectedDevice
    }
}
