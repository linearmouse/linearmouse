// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import SwiftUI

class DeviceIndicatorState: ObservableObject {
    static let shared = DeviceIndicatorState()

    @Published var activeDeviceName: String?

    private var subscriptions = Set<AnyCancellable>()

    init() {
        deviceState.$currentDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshActiveDeviceName()
            }
            .store(in: &subscriptions)

        DeviceManager.shared
            .$receiverPairedDeviceIdentities
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshActiveDeviceName()
            }
            .store(in: &subscriptions)

        DevicePickerState.shared
            .objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshActiveDeviceName()
            }
            .store(in: &subscriptions)
    }
}

extension DeviceIndicatorState {
    private var deviceState: DeviceState {
        DeviceState.shared
    }

    private func refreshActiveDeviceName() {
        guard let device = deviceState.currentDeviceRef?.value else {
            activeDeviceName = nil
            return
        }

        if let deviceModel = DevicePickerState.shared.devices.first(where: { $0.deviceRef.value === device }) {
            activeDeviceName = deviceModel.displayName
            return
        }

        activeDeviceName = DeviceManager.shared.displayName(for: device)
    }
}
