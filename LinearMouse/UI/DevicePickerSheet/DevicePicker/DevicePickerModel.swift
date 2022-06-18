// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import SwiftUI

class DevicePickerModel: ObservableObject {
    var subscriptions = Set<AnyCancellable>()

    init() {
        DeviceManager.shared.objectWillChange.sink { [weak self] in
            withAnimation(.easeOut(duration: 0.15)) {
                self?.objectWillChange.send()
            }
        }
        .store(in: &subscriptions)

        DeviceState.shared.objectWillChange.sink { [weak self] in
            withAnimation(.easeOut(duration: 0.15)) {
                self?.objectWillChange.send()
            }
        }
        .store(in: &subscriptions)
    }
}

extension DevicePickerModel {
    var devices: [DeviceModel] {
        DeviceManager.shared.devices
            .map { DeviceModel(device: $0) }
            .sorted { $0.name < $1.name }
    }
}

class DeviceModel {
    let device: Device

    init(device: Device) {
        self.device = device
    }
}

extension DeviceModel {
    var name: String { device.name }

    var category: Device.Category { device.category }

    var isActive: Bool {
        DeviceManager.shared.lastActiveDevice == device
    }

    var isSelected: Bool {
        DeviceState.shared.currentDevice == device
    }

    var isMouse: Bool { device.category == .mouse }

    var isTrackpad: Bool { device.category == .trackpad }
}

extension DeviceModel: Identifiable {
    var id: Device { device }
}
