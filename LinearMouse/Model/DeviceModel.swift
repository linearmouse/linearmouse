// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Combine
import Foundation
import SwiftUI

class DeviceModel: ObservableObject, Identifiable {
    var id = UUID()

    let deviceRef: WeakRef<Device>

    private var subscriptions = Set<AnyCancellable>()

    @Published var isActive = false
    @Published var isSelected = false

    let name: String
    let category: Device.Category

    init(deviceRef: WeakRef<Device>) {
        self.deviceRef = deviceRef

        name = deviceRef.value?.name ?? "(removed)"
        category = deviceRef.value?.category ?? .mouse

        DeviceManager.shared.$lastActiveDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .map { deviceRef.value != nil && $0?.value == deviceRef.value }
            .sink { [weak self] value in
                withAnimation {
                    self?.isActive = value
                }
            }
            .store(in: &subscriptions)

        DeviceState.shared.$currentDeviceRef
            .map { deviceRef.value != nil && $0?.value == deviceRef.value }
            .assign(to: \.isSelected, on: self)
            .store(in: &subscriptions)
    }
}

extension DeviceModel {
    var isMouse: Bool { category == .mouse }
    var isTrackpad: Bool { category == .trackpad }
}
