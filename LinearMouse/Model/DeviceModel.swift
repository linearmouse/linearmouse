// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import SwiftUI

class DeviceModel: ObservableObject, Identifiable {
    let id: Int32

    let deviceRef: WeakRef<Device>

    private var subscriptions = Set<AnyCancellable>()

    @Published var isActive = false

    @Published var name: String
    @Published var displayName: String
    @Published var batteryLevel: Int?
    @Published var pairedReceiverDevices: [ReceiverLogicalDeviceIdentity] = []
    let category: Device.Category

    init(deviceRef: WeakRef<Device>) {
        self.deviceRef = deviceRef
        id = deviceRef.value?.id ?? 0

        let initialName = deviceRef.value?.name ?? "(removed)"
        name = initialName
        displayName = initialName
        batteryLevel = deviceRef.value?.batteryLevel
        category = deviceRef.value?.category ?? .mouse

        DeviceManager.shared
            .$lastActiveDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .map { deviceRef.value != nil && $0?.value == deviceRef.value }
            .sink { [weak self] value in
                self?.isActive = value
            }
            .store(in: &subscriptions)

        DeviceManager.shared
            .$receiverPairedDeviceIdentities
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshReceiverPresentation()
            }
            .store(in: &subscriptions)

        refreshReceiverPresentation()
    }

    func applyVendorSpecificMetadata(_ metadata: VendorSpecificDeviceMetadata?) {
        if let name = metadata?.name {
            self.name = name
        }

        batteryLevel = metadata?.batteryLevel
        refreshReceiverPresentation()
    }

    private func refreshReceiverPresentation() {
        guard let device = deviceRef.value else {
            displayName = "(removed)"
            pairedReceiverDevices = []
            return
        }

        displayName = DeviceManager.shared.displayName(for: device)
        pairedReceiverDevices = DeviceManager.shared.pairedReceiverDevices(for: device)
    }
}

extension DeviceModel {
    var batteryDescription: String? {
        guard pairedReceiverDevices.isEmpty else {
            return nil
        }

        return batteryLevel.map { "\($0)%" }
    }

    var isMouse: Bool {
        category == .mouse
    }

    var isTrackpad: Bool {
        category == .trackpad
    }
}
