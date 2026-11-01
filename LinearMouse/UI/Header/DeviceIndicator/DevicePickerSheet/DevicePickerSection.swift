// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DevicePickerSection: View {
    @Binding var selection: DevicePickerSelection?

    var category: DeviceMatcher.Category
    var title: LocalizedStringKey
    var devices: [DeviceModel]
    var onSelectCategory: (DeviceMatcher.Category) -> Void
    var onSelectDevice: (DevicePickerEntry) -> Void

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

                ForEach(entries) { entry in
                    DevicePickerSectionItem(
                        entry: entry,
                        isSelected: isSelected(entry)
                    ) {
                        selection = .device(entry.deviceRef, entry.matcher)
                        onSelectDevice(entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var entries: [DevicePickerEntry] {
        devices.flatMap(\.pickerEntries)
    }

    private var isCategorySelected: Bool {
        guard case let .category(selectedCategory) = selection else {
            return false
        }

        return selectedCategory == category
    }

    private func isSelected(_ entry: DevicePickerEntry) -> Bool {
        guard case let .device(selectedDeviceRef, matcher) = selection,
              let selectedDevice = selectedDeviceRef.value,
              entry.deviceRef.value === selectedDevice else {
            return false
        }

        return matcher.condition.isSatisfied(by: entry.matcher)
    }
}
