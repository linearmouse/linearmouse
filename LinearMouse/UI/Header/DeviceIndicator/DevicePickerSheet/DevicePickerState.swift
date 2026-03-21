// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import SwiftUI

class DevicePickerState: ObservableObject {
    static let shared = DevicePickerState()

    var subscriptions = Set<AnyCancellable>()
    private var cachedModels: [Device: DeviceModel] = [:]

    @Published var devices: [DeviceModel] = []

    init() {
        DeviceManager.shared
            .$devices
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [weak self] value in
                self?.updateDevices(with: value)
            }
            .store(in: &subscriptions)
    }

    private func updateDevices(with devices: [Device]) {
        let previousIDs = self.devices.map(\.id)
        let nextDevices = devices.map { device in
            if let existingModel = cachedModels[device] {
                DevicePickerBatteryCoordinator.shared.refresh(existingModel)
                return existingModel
            }

            let model = DeviceModel(deviceRef: WeakRef(device))
            cachedModels[device] = model
            DevicePickerBatteryCoordinator.shared.refresh(model)
            return model
        }

        cachedModels = cachedModels.filter { devices.contains($0.key) }
        let nextIDs = nextDevices.map(\.id)

        guard previousIDs != nextIDs else {
            self.devices = nextDevices
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            self.devices = nextDevices
        }
    }
}
