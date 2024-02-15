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

    func allDeviceSpecficSchemes(of device: Device) -> [EnumeratedSequence<[Scheme]>.Element] {
        schemes.enumerated().filter { _, scheme in
            guard scheme.isDeviceSpecific else { return false }
            guard scheme.if?.count == 1, let `if` = scheme.if?.first else { return false }
            guard `if`.device?.match(with: device) == true else { return false }
            return true
        }
    }

    enum SchemeIndex {
        case at(Int)
        case insertAt(Int)
    }

    func schemeIndex(ofDevice device: Device, ofApp app: String?) -> SchemeIndex {
        let allDeviceSpecificSchemes = allDeviceSpecficSchemes(of: device)

        guard let first = allDeviceSpecificSchemes.first,
              let last = allDeviceSpecificSchemes.last else {
            return .insertAt(schemes.endIndex)
        }

        if let (index, _) = allDeviceSpecificSchemes
            .first(where: { _, scheme in scheme.if?.first?.app == app }) {
            return .at(index)
        }

        return .insertAt(app == nil ? first.offset : last.offset + 1)
    }

    var scheme: Scheme {
        get {
            guard let device = device else {
                return Scheme()
            }

            if case let .at(index) = schemeIndex(ofDevice: device, ofApp: currentApp) {
                return schemes[index]
            }

            return Scheme(if: [
                .init(device: .init(of: device), app: currentApp)
            ])
        }

        set {
            guard let device = device else { return }

            switch schemeIndex(ofDevice: device, ofApp: currentApp) {
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

        return configurationState.configuration.matchScheme(withDevice: device, withApp: currentApp)
    }
}
