// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import Foundation
import SwiftUI

class DeviceModel: ObservableObject {
    let device: Device

    private var subscriptions = Set<AnyCancellable>()

    @Published var isActive = false
    @Published var isSelected = false

    init(device: Device) {
        self.device = device

        DeviceManager.shared.$lastActiveDevice
            .map { $0 == device }
            .sink { [weak self] value in
                withAnimation {
                    self?.isActive = value
                }
            }
            .store(in: &subscriptions)

        DeviceState.shared.$currentDevice
            .map { $0 == device }
            .assign(to: \.isSelected, on: self)
            .store(in: &subscriptions)
    }
}

extension DeviceModel {
    var name: String { device.name }

    var category: Device.Category { device.category }

    var isMouse: Bool { device.category == .mouse }

    var isTrackpad: Bool { device.category == .trackpad }
}

extension DeviceModel: Identifiable {
    var id: Device { device }
}
