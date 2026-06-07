// MIT License
// Copyright (c) 2021-2026 LinearMouse

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

        deviceState.$currentDeviceMatcher
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

    private var deviceMatcher: DeviceMatcher? {
        deviceState.currentDeviceMatcher
    }

    private func deviceConditionMatches(
        _ conditionDeviceMatcher: DeviceMatcher,
        targetMatcher: DeviceMatcher?,
        targetDevice: Device?
    ) -> Bool {
        if let targetCategory = targetMatcher?.categoryOnlyValue {
            return conditionDeviceMatcher == DeviceMatcher(category: targetCategory)
        }

        if conditionDeviceMatcher.categoryOnlyValue != nil {
            return false
        }

        if let targetDevice {
            return conditionDeviceMatcher.match(with: targetDevice)
        }

        guard let targetMatcher else {
            return false
        }

        return conditionDeviceMatcher.match(with: targetMatcher)
    }

    private func hasMatchingSchemes(
        for matcher: DeviceMatcher?,
        device: Device?,
        app: AppTarget?,
        display: String?
    ) -> Bool {
        let (appId, processPath) = extractAppComponents(from: app)

        return schemes.contains { scheme in
            guard let conditions = scheme.if else {
                return false
            }

            return conditions.contains { condition in
                guard let deviceMatcher = condition.device,
                      deviceConditionMatches(deviceMatcher, targetMatcher: matcher, targetDevice: device) else {
                    return false
                }

                let appMatches = condition.app == appId && condition.processPath == processPath
                let displayMatches = condition.display == display

                return appMatches && displayMatches
            }
        }
    }

    private func deleteMatchingSchemes(
        for matcher: DeviceMatcher?,
        device: Device?,
        app: AppTarget?,
        display: String?
    ) {
        let (appId, processPath) = extractAppComponents(from: app)

        schemes.removeAll { scheme in
            guard let conditions = scheme.if else {
                return false
            }

            return conditions.contains { condition in
                guard let deviceMatcher = condition.device,
                      deviceConditionMatches(deviceMatcher, targetMatcher: matcher, targetDevice: device) else {
                    return false
                }

                let appMatches = condition.app == appId && condition.processPath == processPath
                let displayMatches = condition.display == display

                return appMatches && displayMatches
            }
        }
    }

    var isSchemeValid: Bool {
        guard deviceMatcher != nil else {
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

    var targetSpecificSchemes: [EnumeratedSequence<[Scheme]>.Element] {
        guard let deviceMatcher else {
            return []
        }

        if let category = deviceMatcher.categoryOnlyValue {
            return schemes.allDeviceCategorySpecificSchemes(of: category)
        }

        return schemes.allDeviceMatcherSpecificSchemes(of: deviceMatcher)
    }

    var scheme: Scheme {
        get {
            guard let deviceMatcher else {
                return Scheme()
            }

            let (app, processPath) = extractAppComponents(from: currentApp)

            if case let .at(index) = schemes.schemeIndex(
                ofDeviceMatcher: deviceMatcher,
                ofApp: app,
                ofProcessPath: processPath,
                ofDisplay: currentDisplay
            ) {
                return schemes[index]
            }

            var ifCondition = Scheme.If(device: deviceMatcher)
            ifCondition.app = app
            ifCondition.processPath = processPath
            ifCondition.display = currentDisplay

            return Scheme(if: [ifCondition])
        }

        set {
            guard let deviceMatcher else {
                return
            }

            let (app, processPath) = extractAppComponents(from: currentApp)

            switch schemes.schemeIndex(
                ofDeviceMatcher: deviceMatcher,
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

    var deviceScheme: Scheme {
        get {
            guard let device else {
                return Scheme()
            }

            if case let .at(index) = schemes.schemeIndex(
                ofDevice: device,
                ofApp: nil,
                ofProcessPath: nil,
                ofDisplay: nil
            ) {
                return schemes[index]
            }

            return Scheme(if: [Scheme.If(device: .init(of: device))])
        }

        set {
            guard let device else {
                return
            }

            switch schemes.schemeIndex(
                ofDevice: device,
                ofApp: nil,
                ofProcessPath: nil,
                ofDisplay: nil
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
        guard let deviceMatcher else {
            return Scheme()
        }

        let (app, processPath) = extractAppComponents(from: currentApp)

        return configurationState.configuration.matchScheme(
            withDeviceMatcher: deviceMatcher,
            withApp: app,
            withDisplay: currentDisplay,
            withProcessPath: processPath
        )
    }

    var hasMatchingSchemes: Bool {
        hasMatchingSchemes(forApp: currentApp, forDisplay: currentDisplay)
    }

    func hasMatchingSchemes(for matcher: DeviceMatcher?, forApp app: AppTarget?, forDisplay display: String?) -> Bool {
        hasMatchingSchemes(for: matcher, device: nil, app: app, display: display)
    }

    func hasMatchingSchemes(for device: Device?, forApp app: AppTarget?, forDisplay display: String?) -> Bool {
        hasMatchingSchemes(for: device.map { DeviceMatcher(of: $0) }, device: device, app: app, display: display)
    }

    func hasMatchingSchemes(forApp app: AppTarget?, forDisplay display: String?) -> Bool {
        hasMatchingSchemes(for: deviceMatcher, device: nil, app: app, display: display)
    }

    func deleteMatchingSchemes() {
        deleteMatchingSchemes(forApp: currentApp, forDisplay: currentDisplay)
    }

    func deleteMatchingSchemes(for matcher: DeviceMatcher?, forApp app: AppTarget?, forDisplay display: String?) {
        deleteMatchingSchemes(for: matcher, device: nil, app: app, display: display)
    }

    func deleteMatchingSchemes(for device: Device?, forApp app: AppTarget?, forDisplay display: String?) {
        deleteMatchingSchemes(for: device.map { DeviceMatcher(of: $0) }, device: device, app: app, display: display)
    }

    func deleteMatchingSchemes(forApp app: AppTarget?, forDisplay display: String?) {
        deleteMatchingSchemes(for: deviceMatcher, device: nil, app: app, display: display)
    }
}
