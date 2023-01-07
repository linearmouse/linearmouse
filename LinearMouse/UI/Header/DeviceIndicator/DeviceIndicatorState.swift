// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import PointerKit
import SwiftUI

class DeviceIndicatorState: ObservableObject {
    @Published var activeDeviceName: String?

    private var subscriptions = Set<AnyCancellable>()

    init() {
        deviceState.$currentDevice.sink { [weak self] device in
            self?.activeDeviceName = device?.name
        }.store(in: &subscriptions)
    }
}

extension DeviceIndicatorState {
    private var deviceState: DeviceState { DeviceState.shared }
}
