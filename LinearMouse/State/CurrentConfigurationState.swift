// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import Foundation

class CurrentConfigurationState: ObservableObject {
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

extension CurrentConfigurationState {
    private var device: Device? {
        DeviceState.shared.currentDevice
    }

    var scheme: Scheme {
        get {
            configurationState.getSchemeIndex(forDevice: device)
                .map { configurationState.configuration.schemes[$0] }
                ?? configurationState.configuration.matchedScheme(withDevice: device)
        }
        set {
            guard let index = configurationState.getSchemeIndex(forDevice: device) else {
                configurationState.configuration.schemes.append(newValue)
                return
            }

            configurationState.configuration.schemes[index] = newValue
        }
    }
}
