// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import Defaults

extension Defaults.Keys {
    static let shouldSwitchToActiveDevice = Key<Bool>("shouldSwitchToActiveDevice", default: true)

    static let userSelectedDevice = Key<PersistedDevice?>("userSelectedDevice", default: nil)
}

class DeviceState: ObservableObject {
    static let shared = DeviceState()

    private var subscriptions = Set<AnyCancellable>()

    @Published var currentDevice: Device? {
        didSet {
            guard !Defaults[.shouldSwitchToActiveDevice] else {
                return
            }

            Defaults[.userSelectedDevice] = currentDevice.map { PersistedDevice(fromDevice: $0) }
        }
    }

    init() {
        Defaults.observe(keys: .shouldSwitchToActiveDevice, .userSelectedDevice) { [weak self] in
            self?.updateCurrentDevice()
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
        guard !Defaults[.shouldSwitchToActiveDevice] else {
            currentDevice = lastActiveDevice
            return
        }

        guard let userSelectedDevice = Defaults[.userSelectedDevice] else {
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
