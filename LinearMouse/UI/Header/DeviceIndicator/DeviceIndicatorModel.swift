// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import PointerKit
import SwiftUI

class DeviceIndicatorModel: ObservableObject {
    @Published var activeDeviceName: String?

    private var subscriptions = Set<AnyCancellable>()

    init() {
        deviceState.$currentDevice.sink { [weak self] device in
            self?.activeDeviceName = device?.name
        }.store(in: &subscriptions)
    }
}

extension DeviceIndicatorModel {
    private var deviceState: DeviceState { DeviceState.shared }
}
