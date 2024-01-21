// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Combine
import Foundation

class SchemeState: ObservableObject {
    static let shared = SchemeState()

    private let configurationState: ConfigurationState = .shared
    private let deviceState: DeviceState = .shared

    private var subscriptions = Set<AnyCancellable>()

    @Published var currentApp: String?
    @Published var currentDisplay: String?

    init() {
        configurationState.$configuration
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        deviceState.$currentDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
}

extension SchemeState {
    private var device: Device? {
        deviceState.currentDeviceRef?.value
    }

    var isSchemeValid: Bool {
        guard device != nil else {
            return false
        }

        return true
    }

    var schemes: [Scheme] {
        get { configurationState.configuration.schemes }
        set { configurationState.configuration.schemes = newValue }
    }

    var currentAppName: String? {
        guard let currentApp = currentApp else { return nil }
        return try? readInstalledApp(bundleIdentifier: currentApp)?.bundleName ?? currentApp
    }

    var scheme: Scheme {
        get {
            guard let device = device else {
                return Scheme()
            }

            if case let .at(index) = schemes.schemeIndex(
                ofDevice: device,
                ofApp: currentApp,
                ofDisplay: currentDisplay
            ) {
                return schemes[index]
            }

            return Scheme(if: [
                .init(device: .init(of: device), app: currentApp, display: currentDisplay)
            ])
        }

        set {
            guard let device = device else { return }

            switch schemes.schemeIndex(ofDevice: device, ofApp: currentApp, ofDisplay: currentDisplay) {
            case let .at(index):
                schemes[index] = newValue
            case let .insertAt(index):
                schemes.insert(newValue, at: index)
            }
        }
    }

    var mergedScheme: Scheme {
        guard let device = device else {
            return Scheme()
        }

        return configurationState.configuration.matchScheme(
            withDevice: device,
            withApp: currentApp,
            withDisplay: currentDisplay
        )
    }
}
