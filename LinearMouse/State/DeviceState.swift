// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import Defaults

extension Defaults.Keys {
    static let autoSelectActiveDevice = Key<Bool>("autoSelectActiveDevice", default: true)

    static let selectedDevice = Key<DeviceMatcher?>("selectedDevice", default: nil)
}

class DeviceState: ObservableObject {
    static let shared = DeviceState()

    private var subscriptions = Set<AnyCancellable>()

    @Published var currentDevice: Device? {
        didSet {
            guard !Defaults[.autoSelectActiveDevice] else {
                return
            }

            Defaults[.selectedDevice] = currentDevice.map { DeviceMatcher(of: $0) }
        }
    }

    init() {
        Defaults.observe(keys: .autoSelectActiveDevice, .selectedDevice) { [weak self] in
            self?.updateCurrentDevice()
        }
        .tieToLifetime(of: self)

        Defaults.observe(.autoSelectActiveDevice) { change in
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
        guard !Defaults[.autoSelectActiveDevice] else {
            currentDevice = lastActiveDevice
            return
        }

        guard let userSelectedDevice = Defaults[.selectedDevice] else {
            currentDevice = lastActiveDevice
            return
        }

        let matchedDevice = deviceManager.devices.first { userSelectedDevice.strictMatch(with: $0) }

        currentDevice = matchedDevice ?? lastActiveDevice
    }

    private func updateCurrentDevice() {
        updateCurrentDevice(lastActiveDevice: deviceManager.lastActiveDevice)
    }
}
