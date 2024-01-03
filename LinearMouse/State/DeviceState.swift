// MIT License
// Copyright (c) 2021-2024 LinearMouse

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

    @Published var currentDeviceRef: WeakRef<Device>? {
        didSet {
            guard !Defaults[.autoSwitchToActiveDevice] else {
                return
            }

            Defaults[.selectedDevice] = currentDeviceRef?.value.map { DeviceMatcher(of: $0) }
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
    }
}

extension DeviceState {
    private var deviceManager: DeviceManager { DeviceManager.shared }

    private func updateCurrentDeviceRef(lastActiveDeviceRef: WeakRef<Device>?) {
        guard !Defaults[.autoSwitchToActiveDevice] else {
            currentDeviceRef = lastActiveDeviceRef
            return
        }

        guard let userSelectedDevice = Defaults[.selectedDevice] else {
            currentDeviceRef = lastActiveDeviceRef
            return
        }

        let matchedDeviceRef = deviceManager.devices
            .first { userSelectedDevice.match(with: $0) }
            .map { WeakRef($0) }

        currentDeviceRef = matchedDeviceRef ?? lastActiveDeviceRef
    }

    private func updateCurrentDevice() {
        updateCurrentDeviceRef(lastActiveDeviceRef: deviceManager.lastActiveDeviceRef)
    }
}
