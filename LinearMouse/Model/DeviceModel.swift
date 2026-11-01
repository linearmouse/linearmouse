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
    /// Battery levels of `pairedReceiverDevices`, by slot.
    @Published var pairedReceiverDeviceBatteryLevels: [UInt8: Int] = [:]
    @Published var activeLogicalDevice: ReceiverLogicalDeviceIdentity?
    /// The device is a receiver whose connected devices are known, possibly none.
    @Published var hasDiscoveredReceiverDevices = false
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

        BatteryDeviceMonitor.shared
            .$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshBatteryLevel()
            }
            .store(in: &subscriptions)

        refreshReceiverPresentation()
        refreshBatteryLevel()
    }

    private func refreshReceiverPresentation() {
        guard let device = deviceRef.value else {
            name = "(removed)"
            displayName = "(removed)"
            pairedReceiverDevices = []
            activeLogicalDevice = nil
            hasDiscoveredReceiverDevices = false
            return
        }

        let preferredName = DeviceManager.shared.preferredName(for: device, fallback: name)
        let pairedDevices = DeviceManager.shared.pairedReceiverDevices(for: device)

        name = preferredName
        pairedReceiverDevices = pairedDevices
        activeLogicalDevice = device.activeLogicalDeviceIdentity
        hasDiscoveredReceiverDevices = DeviceManager.shared.hasDiscoveredReceiverDevices(for: device)
        displayName = DeviceManager.displayName(baseName: preferredName, pairedDevices: pairedDevices)
        refreshBatteryLevel()
    }

    private func refreshBatteryLevel() {
        guard let device = deviceRef.value else {
            batteryLevel = nil
            pairedReceiverDeviceBatteryLevels = [:]
            return
        }

        batteryLevel = BatteryDeviceMonitor.shared.currentDeviceBatteryLevel(for: device) ?? device.batteryLevel
        pairedReceiverDeviceBatteryLevels = pairedReceiverDevices.reduce(into: [:]) { levels, identity in
            levels[identity.slot] = BatteryDeviceMonitor.shared.batteryLevel(of: identity)
        }
    }
}

/// One selectable device: a physical device, or a device behind it such as
/// a mouse paired to a receiver.
struct DevicePickerEntry: Identifiable {
    let id: String
    let deviceRef: WeakRef<Device>
    let matcher: DeviceMatcher
    let name: String
    let batteryLevel: Int?
    let isActive: Bool
    let isPhysicalDevice: Bool
}

extension DeviceModel {
    private var logicalDeviceEntries: [DevicePickerEntry] {
        guard let device = deviceRef.value else {
            return []
        }

        return pairedReceiverDevices.compactMap { identity in
            guard let matcher = DeviceMatcher(of: device, logicalDevice: identity) else {
                return nil
            }

            return DevicePickerEntry(
                id: "\(id)-\(identity.slot)",
                deviceRef: deviceRef,
                matcher: matcher,
                name: identity.name,
                batteryLevel: pairedReceiverDeviceBatteryLevels[identity.slot],
                isActive: isActive && activeLogicalDevice?.slot == identity.slot,
                isPhysicalDevice: false
            )
        }
    }

    /// The devices behind this one replace it in the device picker. A
    /// receiver is still listed while it cannot tell which device behind it is
    /// in use, since only its own schemes apply then: while several are
    /// connected, or while it is in use but nothing behind it is known yet.
    /// It is not listed once discovery finds nothing connected to it. Schemes
    /// written for it keep applying, inherited by the devices behind it.
    var pickerEntries: [DevicePickerEntry] {
        guard let device = deviceRef.value else {
            return []
        }

        let logicalEntries = logicalDeviceEntries
        // Listed devices are exactly those with a matcher.
        let routesToListedDevice = activeLogicalDevice
            .flatMap { DeviceMatcher(of: device, logicalDevice: $0) } != nil
        let hasNothingConnected = hasDiscoveredReceiverDevices && pairedReceiverDevices.isEmpty && !isActive
        guard !routesToListedDevice, !hasNothingConnected else {
            return logicalEntries
        }

        let physicalEntry = DevicePickerEntry(
            id: "\(id)",
            deviceRef: deviceRef,
            matcher: DeviceMatcher(of: device),
            name: logicalEntries.isEmpty ? displayName : name,
            batteryLevel: pairedReceiverDevices.isEmpty ? batteryLevel : nil,
            isActive: isActive && !routesToListedDevice,
            isPhysicalDevice: true
        )
        return [physicalEntry] + logicalEntries
    }

    /// The name of the device `matcher` selects on this physical device.
    func name(for matcher: DeviceMatcher) -> String {
        logicalDeviceEntries.first { matcher.condition.isSatisfied(by: $0.matcher) }?.name ?? displayName
    }

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
