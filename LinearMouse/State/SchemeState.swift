// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation

class SchemeState: ObservableObject {
    static let shared = SchemeState()

    private let configurationState: ConfigurationState = .shared
    private let deviceState: DeviceState = .shared

    private var subscriptions = Set<AnyCancellable>()

    @Published var currentApp: String?

    init() {
        configurationState.$configuration
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        deviceState.$currentDevice
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
}

extension SchemeState {
    private var device: Device? {
        deviceState.currentDevice
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

            if let index = configurationState.getSchemeIndex(forDevice: device, forApp: currentApp) {
                return configurationState.configuration.schemes[index]
            }

            return Scheme(if: [
                .init(device: .init(of: device), app: currentApp)
            ])
        }

        set {
            guard let device = device else { return }

            guard let index = configurationState.getSchemeIndex(forDevice: device, forApp: currentApp) else {
                // TODO: Insert orders
                configurationState.configuration.schemes.append(newValue)
                return
            }

            configurationState.configuration.schemes[index] = newValue
        }
    }

    var mergedScheme: Scheme {
        guard let device = device else {
            return Scheme()
        }

        return configurationState.configuration.matchScheme(withDevice: device, withApp: currentApp)
    }
}
