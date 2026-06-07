// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

enum DevicePickerSelection {
    case category(DeviceMatcher.Category)
    case device(WeakRef<Device>)

    var deviceRef: WeakRef<Device>? {
        guard case let .device(deviceRef) = self else {
            return nil
        }

        return deviceRef
    }

    var deviceMatcher: DeviceMatcher? {
        switch self {
        case let .category(category):
            return DeviceMatcher(category: category)
        case let .device(deviceRef):
            return deviceRef.value.map { DeviceMatcher(of: $0) }
        }
    }
}

struct DevicePicker: View {
    @ObservedObject var state = DevicePickerState.shared

    @Binding var selection: DevicePickerSelection?
    var onSelectCategory: (DeviceMatcher.Category) -> Void
    var onSelectDevice: (WeakRef<Device>) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DevicePickerSection(
                    selection: $selection,
                    category: .mouse,
                    title: "Mouse",
                    devices: state.devices.filter(\.isMouse),
                    onSelectCategory: onSelectCategory,
                    onSelectDevice: onSelectDevice
                )
                DevicePickerSection(
                    selection: $selection,
                    category: .trackpad,
                    title: "Trackpad",
                    devices: state.devices.filter(\.isTrackpad),
                    onSelectCategory: onSelectCategory,
                    onSelectDevice: onSelectDevice
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 350)
    }
}
