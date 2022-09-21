// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log

protocol EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent?
}

func transformEvent(_ event: CGEvent) -> CGEvent? {
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTransformer")

    var transformed: CGEvent? = event

    let view = MouseEventView(event)

    let device = DeviceManager.shared.lastActiveDevice

    let mergedScheme = ConfigurationState.shared.configuration.matchedScheme(withDevice: device,
                                                                             withPid: view.targetPid)

    os_log("Using scheme: %{public}@ (device: %{public}@, app: %{public}@)", log: log, type: .debug,
           String(describing: mergedScheme),
           String(describing: device),
           view.targetPid?.bundleIdentifier ?? "(nil)")

    // TODO: Cache transformers
    let transformers = buildEventTransformers(for: mergedScheme)

    for transformer in transformers {
        if let transformedEvent = transformed {
            transformed = transformer.transform(transformedEvent)
        }
    }

    return transformed
}

func buildEventTransformers(for scheme: Scheme) -> [EventTransformer] {
    var transformers: [EventTransformer] = []

    if let reverse = scheme.scrolling?.reverse {
        let vertical = reverse.vertical ?? false
        let horizontal = reverse.horizontal ?? false

        if vertical || horizontal {
            transformers.append(ReverseScrolling(vertically: vertical, horizontally: horizontal))
        }
    }

    if let distance = scheme.scrolling?.distance {
        transformers.append(LinearScrolling(distance: distance))
    }

    if let modifiers = scheme.scrolling?.modifiers {
        transformers.append(ModifierActions(modifiers: modifiers))
    }

    if let mappings = scheme.buttons?.mappings {
        transformers.append(ButtonActions(mappings: mappings))
    }

    if scheme.buttons?.universalBackForward == true {
        transformers.append(UniversalBackForward())
    }

    return transformers
}
