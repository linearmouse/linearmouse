// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

enum DevicePickerSelection {
    case category(DeviceMatcher.Category)
    /// A device on `deviceRef`: the physical device itself or a device behind
    /// it. The matcher is kept so that the selection survives reconnection.
    case device(WeakRef<Device>, DeviceMatcher)

    var deviceRef: WeakRef<Device>? {
        guard case let .device(deviceRef, _) = self else {
            return nil
        }

        return deviceRef
    }

    var deviceMatcher: DeviceMatcher? {
        switch self {
        case let .category(category):
            return DeviceMatcher(category: category)
        case let .device(_, matcher):
            return matcher
        }
    }

    static func activeDevice(_ deviceRef: WeakRef<Device>) -> Self? {
        deviceRef.value.map { .device(deviceRef, DeviceMatcher(activeOf: $0)) }
    }
}

struct DevicePicker: View {
    @ObservedObject var state = DevicePickerState.shared

    @Binding var selection: DevicePickerSelection?
    var onSelectCategory: (DeviceMatcher.Category) -> Void
    var onSelectDevice: (DevicePickerEntry) -> Void

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
