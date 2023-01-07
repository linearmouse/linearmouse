// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation

class SchemeState: ObservableObject {
    private let configurationState = ConfigurationState.shared

    private var subscriptions = Set<AnyCancellable>()

    init() {
        configurationState.$configuration.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &subscriptions)

        configurationState.$currentDeviceSchemeIndex.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &subscriptions)
    }
}

extension SchemeState {
    private var device: Device? {
        DeviceState.shared.currentDevice
    }

    var isSchemeValid: Bool {
        guard device != nil else {
            return false
        }

        return true
    }

    var scheme: Scheme {
        get {
            guard let device = device else {
                return Scheme()
            }

            return configurationState.getSchemeIndex(forDevice: device)
                .map { configurationState.configuration.schemes[$0] }
                ?? configurationState.configuration.matchScheme(withDevice: device)
        }

        set {
            guard let device = device else { return }

            guard let index = configurationState.getSchemeIndex(forDevice: device) else {
                configurationState.configuration.schemes.append(newValue)
                return
            }

            configurationState.configuration.schemes[index] = newValue
        }
    }
}
