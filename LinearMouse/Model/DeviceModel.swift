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
    private let baseName: String

    init(deviceRef: WeakRef<Device>) {
        self.deviceRef = deviceRef
        id = deviceRef.value?.id ?? 0

        let initialName = deviceRef.value?.name ?? "(removed)"
        baseName = initialName
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

        BatteryDeviceMonitor.shared
            .$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshBatteryLevel()
            }
            .store(in: &subscriptions)

        refreshReceiverPresentation()
        refreshBatteryLevel()

        DevicePickerBatteryCoordinator.shared.refresh(self)
    }

    func applyVendorSpecificMetadata(_ metadata: VendorSpecificDeviceMetadata?) {
        if let name = metadata?.name {
            self.name = name
        }

        batteryLevel = metadata?.batteryLevel
        refreshReceiverPresentation()
        refreshBatteryLevel()
    }

    private func refreshReceiverPresentation() {
        guard let device = deviceRef.value else {
            name = "(removed)"
            displayName = "(removed)"
            pairedReceiverDevices = []
            return
        }

        let preferredName = DeviceManager.shared.preferredName(for: device, fallback: name)
        let pairedDevices = DeviceManager.shared.pairedReceiverDevices(for: device)

        name = preferredName
        pairedReceiverDevices = pairedDevices
        displayName = DeviceManager.displayName(baseName: preferredName, pairedDevices: pairedDevices)
    }

    private func refreshBatteryLevel() {
        guard let device = deviceRef.value else {
            batteryLevel = nil
            return
        }

        batteryLevel = BatteryDeviceMonitor.shared.currentDeviceBatteryLevel(for: device) ?? device.batteryLevel
    }

    func resetVendorSpecificMetadata() {
        name = baseName
        refreshReceiverPresentation()
        refreshBatteryLevel()
    }
}

extension DeviceModel {
    var batteryDescription: String? {
        guard pairedReceiverDevices.isEmpty else {
            return nil
        }

        return batteryLevel.map(formattedPercent)
    }

    var isMouse: Bool {
        category == .mouse
    }

    var isTrackpad: Bool {
        category == .trackpad
    }
}
