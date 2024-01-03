// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Combine
import SwiftUI

class DevicePickerState: ObservableObject {
    static let shared = DevicePickerState()

    var subscriptions = Set<AnyCancellable>()

    @Published var devices: [DeviceModel] = []

    init() {
        DeviceManager.shared.$devices
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .map {
                $0
                    .map { DeviceModel(deviceRef: WeakRef($0)) }
            }
            .sink { [weak self] value in
                withAnimation {
                    self?.devices = value
                }
            }
            .store(in: &subscriptions)
    }
}
