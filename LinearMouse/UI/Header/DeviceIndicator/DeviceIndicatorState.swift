// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Combine
import PointerKit
import SwiftUI

class DeviceIndicatorState: ObservableObject {
    static let shared = DeviceIndicatorState()

    @Published var activeDeviceName: String?

    private var subscriptions = Set<AnyCancellable>()

    init() {
        deviceState.$currentDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] deviceRef in
                self?.activeDeviceName = deviceRef?.value?.name
            }
            .store(in: &subscriptions)
    }
}

extension DeviceIndicatorState {
    private var deviceState: DeviceState { DeviceState.shared }
}
