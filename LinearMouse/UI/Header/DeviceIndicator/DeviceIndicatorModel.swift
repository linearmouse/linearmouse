// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import PointerKit
import SwiftUI

class DeviceIndicatorModel: ObservableObject {
    @Published var activeDeviceName: String = "(Unknown)"

    private var subscription: AnyCancellable?

    init() {
        subscription = DeviceManager.shared.$lastActiveDevice
            .map { $0?.name ?? "(Unknown)" }
            .assign(to: \.activeDeviceName, on: self)
    }
}
