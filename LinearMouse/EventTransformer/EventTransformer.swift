// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import LRUCache
import os.log

protocol EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent?
}

extension [EventTransformer]: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        var event: CGEvent? = event

        for eventTransformer in self {
            event = event.flatMap { eventTransformer.transform($0) }
        }

        return event
    }
}

var eventTransformerCache = LRUCache<EventTransformerCacheKey, EventTransformer>(countLimit: 1)

class EventTransformerCacheKey: Equatable, Hashable {
    let version: Int
    let device: WeakRef<Device>?
    let pid: pid_t?

    init(version: Int, device: Device?, pid: pid_t?) {
        self.version = version
        self.device = device.map { WeakRef($0) }
        self.pid = pid
    }

    static func == (lhs: EventTransformerCacheKey, rhs: EventTransformerCacheKey) -> Bool {
        lhs.version == rhs.version && lhs.device == rhs.device && lhs.pid == rhs.pid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(device)
        hasher.combine(pid)
    }
}

func getEventTransformer(forDevice device: Device?, forPid pid: pid_t? = nil) -> EventTransformer {
    let cacheKey = EventTransformerCacheKey(version: ConfigurationState.shared.version, device: device, pid: pid)

    if let eventTransformer = eventTransformerCache.value(forKey: cacheKey) {
        return eventTransformer
    }

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

    eventTransformerCache.setValue(transformers, forKey: cacheKey)

    return transformers
}
