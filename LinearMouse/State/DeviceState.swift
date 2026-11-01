// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let autoSwitchToActiveDevice = Key<Bool>("autoSwitchToActiveDevice", default: true)

    static let selectedDevice = Key<DeviceMatcher?>("selectedDevice", default: nil)
}

class DeviceState: ObservableObject {
    static let shared = DeviceState()

    private var subscriptions = Set<AnyCancellable>()
    private var isUpdatingCurrentDeviceRef = false

    @Published var currentDeviceMatcher: DeviceMatcher?

    @Published var currentDeviceRef: WeakRef<Device>? {
        didSet {
            guard !isUpdatingCurrentDeviceRef, !Defaults[.autoSwitchToActiveDevice] else {
                return
            }

            let currentDeviceMatcher = currentDeviceRef?.value.map { DeviceMatcher(activeOf: $0) }
            guard Defaults[.selectedDevice] != currentDeviceMatcher else {
                return
            }

            Defaults[.selectedDevice] = currentDeviceMatcher
        }
    }

    init() {
        Defaults.observe(keys: .autoSwitchToActiveDevice, .selectedDevice) { [weak self] in
            self?.updateCurrentDevice()
        }
        .tieToLifetime(of: self)

        Defaults.observe(.autoSwitchToActiveDevice) { change in
            if change.newValue {
                Defaults[.selectedDevice] = nil
            }
        }
        .tieToLifetime(of: self)

        deviceManager.$lastActiveDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] lastActiveDeviceRef in
                self?.updateCurrentDeviceRef(lastActiveDeviceRef: lastActiveDeviceRef)
            }
            .store(in: &subscriptions)

        deviceManager.$devices
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateCurrentDevice()
            }
            .store(in: &subscriptions)

        // The device in use behind a receiver changes with its connections.
        deviceManager.$receiverPairedDeviceIdentities
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateCurrentDevice()
            }
            .store(in: &subscriptions)
    }
}

extension DeviceState {
    private var deviceManager: DeviceManager {
        DeviceManager.shared
    }

    private func setCurrentDeviceRef(_ deviceRef: WeakRef<Device>?) {
        if currentDeviceRef?.value !== deviceRef?.value {
            SettingsState.shared.endButtonMappingRecording()
        }

        isUpdatingCurrentDeviceRef = true
        currentDeviceRef = deviceRef
        isUpdatingCurrentDeviceRef = false
    }

    /// The device in use, which may be a device behind a receiver.
    private func exactMatcher(of deviceRef: WeakRef<Device>?) -> DeviceMatcher? {
        deviceRef?.value.map { DeviceMatcher(activeOf: $0) }
    }

    private func updateCurrentDeviceRef(lastActiveDeviceRef: WeakRef<Device>?) {
        guard !Defaults[.autoSwitchToActiveDevice], let userSelectedDevice = Defaults[.selectedDevice] else {
            setCurrentDeviceRef(lastActiveDeviceRef)
            currentDeviceMatcher = exactMatcher(of: lastActiveDeviceRef)
            return
        }

        let matchedDeviceRef = deviceManager.devices
            // The saved selection may carry the name one connection reported.
            .first { userSelectedDevice.condition.match(with: $0) }
            .map { WeakRef($0) }

        setCurrentDeviceRef(matchedDeviceRef ?? lastActiveDeviceRef)
        currentDeviceMatcher = userSelectedDevice
    }

    private func updateCurrentDevice() {
        updateCurrentDeviceRef(lastActiveDeviceRef: deviceManager.lastActiveDeviceRef)
    }
}
