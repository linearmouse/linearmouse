// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

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

    @Published var currentDevice: Device? {
        didSet {
            guard !Defaults[.autoSwitchToActiveDevice] else {
                return
            }

            Defaults[.selectedDevice] = currentDevice.map { DeviceMatcher(of: $0) }
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

        deviceManager.$lastActiveDevice.sink { [weak self] lastActiveDevice in
            self?.updateCurrentDevice(lastActiveDevice: lastActiveDevice)
        }
        .store(in: &subscriptions)
    }
}

extension DeviceState {
    private var deviceManager: DeviceManager { DeviceManager.shared }

    private func updateCurrentDevice(lastActiveDevice: Device?) {
        guard !Defaults[.autoSwitchToActiveDevice] else {
            currentDevice = lastActiveDevice
            return
        }

        guard let userSelectedDevice = Defaults[.selectedDevice] else {
            currentDevice = lastActiveDevice
            return
        }

        let matchedDevice = deviceManager.devices.first { userSelectedDevice.match(with: $0) }

        currentDevice = matchedDevice ?? lastActiveDevice
    }

    private func updateCurrentDevice() {
        updateCurrentDevice(lastActiveDevice: deviceManager.lastActiveDevice)
    }
}
