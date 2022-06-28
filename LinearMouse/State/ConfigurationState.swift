// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import AppKit
import Combine
import Foundation
import os.log
import SwiftUI

class ConfigurationState: ObservableObject {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    static let shared = ConfigurationState()

    let configurationPath = URL(
        fileURLWithPath: ".config/linearmouse/linearmouse.json",
        relativeTo: FileManager.default.homeDirectoryForCurrentUser
    )

    @Published var configuration = Configuration() {
        didSet {
            updateActiveScheme()

            guard shouldAutoSaveConfiguration else {
                return
            }

            os_log("Saving new configuration: %{public}@", log: Self.log, type: .debug,
                   String(describing: configuration))
            save()
        }
    }

    private var shouldAutoSaveConfiguration = true

    @Published var activeScheme: Scheme? {
        didSet {
            // TODO: Refactor: `EventTransformer`s shouldn't be built here.
            // FIXME: The first event after device switching may be handled by the last built `EventTransformer`s.
            eventTransformers = buildEventTransformers()

            guard let activeScheme = activeScheme else {
                os_log("Active scheme is updated: nil", log: Self.log, type: .debug,
                       String(describing: activeScheme))
                return
            }

            os_log("Active scheme is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: activeScheme))
        }
    }

    @Published var eventTransformers: [EventTransformer] = []

    @Published var currentDeviceSchemeIndex: Int? {
        didSet {
            os_log("Current device scheme index is updated: %{public}@", log: Self.log, type: .debug,
                   String(describing: currentDeviceSchemeIndex))
        }
    }

    private var subscriptions = Set<AnyCancellable>()

    init() {
        load()

        DeviceManager.shared.$lastActiveDevice.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateActiveScheme()
            }
        }
        .store(in: &subscriptions)

        DeviceState.shared.$currentDevice.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateCurrentDeviceScheme()
            }
        }
        .store(in: &subscriptions)
    }
}

extension ConfigurationState {
    func load() {
        shouldAutoSaveConfiguration = false
        defer {
            shouldAutoSaveConfiguration = true
        }

        do {
            configuration = try Configuration.load(from: configurationPath)
            updateActiveScheme()
            updateCurrentDeviceScheme()
        } catch CocoaError.fileReadNoSuchFile {
            os_log("No configuration file found, try creating a default one", log: Self.log, type: .debug)
            save()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(
                format: NSLocalizedString("Failed to load the configuration: %@", comment: ""),
                error.localizedDescription
            )
            alert.runModal()
        }
    }

    func save() {
        do {
            try configuration.dump(to: configurationPath)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(
                format: NSLocalizedString("Failed to save the configuration: %@", comment: ""),
                error.localizedDescription
            )
            alert.runModal()
        }
    }

    func updateActiveScheme() {
        activeScheme = configuration.activeScheme
    }

    func updateCurrentDeviceScheme() {
        currentDeviceSchemeIndex = DeviceState.shared.currentDevice.flatMap { device in
            configuration.schemes.firstIndex {
                guard $0.isDeviceSpecific else { return false }

                return $0.if?.contains { $0.isSatisfied(withDevice: device) } == true
            }
        }
    }

    func getSchemeIndex(forDevice device: Device?) -> Int? {
        guard let device = device else {
            return nil
        }

        return configuration.schemes.firstIndex {
            guard $0.isDeviceSpecific else { return false }

            return $0.if?.contains { $0.isSatisfied(withDevice: device) } == true
        }
    }

    func buildEventTransformers() -> [EventTransformer] {
        var transformers: [EventTransformer] = []

        guard let scheme = activeScheme else {
            return transformers
        }

        if let reverse = scheme.scrolling?.reverse {
            let vertical = reverse.vertical ?? false
            let horizontal = reverse.horizontal ?? false

            if vertical || horizontal {
                transformers.append(ReverseScrolling(vertically: vertical, horizontally: horizontal))
            }
        }

        if let distance = scheme.scrolling?.distance {
            if distance.unit == .line {
                transformers.append(LinearScrolling(scrollLines: distance.value))
            }
        }

        if let modifiers = scheme.scrolling?.modifiers {
            transformers.append(ModifierActions(modifiers: modifiers))
        }

        if scheme.buttons?.universalBackForward == true {
            transformers.append(UniversalBackForward())
        }

        return transformers
    }
}
