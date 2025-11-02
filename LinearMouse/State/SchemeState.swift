// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Combine
import Foundation

class SchemeState: ObservableObject {
    static let shared = SchemeState()

    private let configurationState: ConfigurationState = .shared
    private let deviceState: DeviceState = .shared

    private var subscriptions = Set<AnyCancellable>()

    @Published var currentApp: AppTarget?
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
        switch currentApp {
        case .none:
            return nil
        case let .bundle(bundleIdentifier):
            return try? readInstalledApp(bundleIdentifier: bundleIdentifier)?.bundleName ?? bundleIdentifier
        case let .executable(path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    var scheme: Scheme {
        get {
            guard let device else {
                return Scheme()
            }

            let (app, processPath) = extractAppComponents(from: currentApp)

            if case let .at(index) = schemes.schemeIndex(
                ofDevice: device,
                ofApp: app,
                ofProcessPath: processPath,
                ofDisplay: currentDisplay
            ) {
                return schemes[index]
            }

            var ifCondition = Scheme.If(device: .init(of: device))
            ifCondition.app = app
            ifCondition.processPath = processPath
            ifCondition.display = currentDisplay

            return Scheme(if: [ifCondition])
        }

        set {
            guard let device else {
                return
            }

            let (app, processPath) = extractAppComponents(from: currentApp)

            switch schemes.schemeIndex(
                ofDevice: device,
                ofApp: app,
                ofProcessPath: processPath,
                ofDisplay: currentDisplay
            ) {
            case let .at(index):
                schemes[index] = newValue
            case let .insertAt(index):
                schemes.insert(newValue, at: index)
            }
        }
    }

    private func extractAppComponents(from target: AppTarget?) -> (app: String?, processPath: String?) {
        switch target {
        case .none:
            return (nil, nil)
        case let .bundle(bundleIdentifier):
            return (bundleIdentifier, nil)
        case let .executable(path):
            return (nil, path)
        }
    }

    var mergedScheme: Scheme {
        guard let device else {
            return Scheme()
        }

        let (app, processPath) = extractAppComponents(from: currentApp)

        return configurationState.configuration.matchScheme(
            withDevice: device,
            withApp: app,
            withDisplay: currentDisplay,
            withProcessPath: processPath
        )
    }
}
