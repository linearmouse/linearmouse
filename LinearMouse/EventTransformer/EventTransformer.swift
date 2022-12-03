// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log

protocol EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent?
}

extension [EventTransformer]: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        var transformedEvent: CGEvent? = event

        for eventTransformer in self {
            transformedEvent = transformedEvent.flatMap { eventTransformer.transform($0) }
        }

        return transformedEvent
    }
}

func transformEvent(_ event: CGEvent) -> CGEvent? {
    let view = MouseEventView(event)

    let eventTransformer = buildEventTransformer(forDevice: DeviceManager.shared.lastActiveDevice,
                                                 forPid: view.targetPid)

    return eventTransformer.transform(event)
}

func buildEventTransformer(forDevice device: Device?, forPid pid: pid_t? = nil) -> [EventTransformer] {
    // TODO: Cache

    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTransformer")

    let scheme = ConfigurationState.shared.configuration.matchedScheme(withDevice: device,
                                                                       withPid: pid)

    os_log("Using scheme: %{public}@ (device: %{public}@, app: %{public}@)", log: log, type: .debug,
           String(describing: scheme),
           String(describing: device),
           pid?.bundleIdentifier ?? "(nil)")

    var transformers: [EventTransformer] = []

    if let reverse = scheme.scrolling?.reverse {
        let vertical = reverse.vertical ?? false
        let horizontal = reverse.horizontal ?? false

        if vertical || horizontal {
            transformers.append(ReverseScrolling(vertically: vertical, horizontally: horizontal))
        }
    }

    if let distance = scheme.scrolling?.distance?.horizontal {
        transformers.append(LinearScrollingHorizontal(distance: distance))
    }

    if let distance = scheme.scrolling?.distance?.vertical {
        transformers.append(LinearScrollingVertical(distance: distance))
    }

    if let modifiers = scheme.scrolling?.modifiers {
        transformers.append(ModifierActions(modifiers: modifiers))
    }

    if let mappings = scheme.buttons?.mappings {
        transformers.append(ButtonActions(mappings: mappings))
    }

    if let universalBackForward = scheme.buttons?.universalBackForward,
       universalBackForward != .none {
        transformers.append(UniversalBackForward(universalBackForward: universalBackForward))
    }

    return transformers
}
