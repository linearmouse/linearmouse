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

class EventTransformerCacheKey {
    let version: Int
    let device: WeakRef<Device>?
    let pid: pid_t?

    init(version: Int, device: Device?, pid: pid_t?) {
        self.version = version
        self.device = device.map { WeakRef($0) }
        self.pid = pid
    }
}

extension EventTransformerCacheKey: Equatable, Hashable {
    static func == (lhs: EventTransformerCacheKey, rhs: EventTransformerCacheKey) -> Bool {
        lhs.version == rhs.version && lhs.device == rhs.device && lhs.pid == rhs.pid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(device)
        hasher.combine(pid)
    }
}

extension EventTransformerCacheKey: CustomStringConvertible {
    var description: String {
        "EventTransformerCacheKey(version: \(version), device: \(String(describing: device)), pid: \(String(describing: pid)))"
    }
}

func getEventTransformer(forDevice device: Device?, forPid pid: pid_t? = nil) -> EventTransformer {
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTransformer")

    let cacheKey = EventTransformerCacheKey(version: ConfigurationState.shared.version, device: device, pid: pid)

    if let eventTransformer = eventTransformerCache.value(forKey: cacheKey) {
        return eventTransformer
    }

    let scheme = ConfigurationState.shared.configuration.matchScheme(withDevice: device,
                                                                     withPid: pid)

    // TODO: Patch EventTransformer instead of rebuilding it

    os_log("Initialize EventTransformer with scheme: %{public}@ (cacheKey=%{public}@)",
           log: log, type: .debug,
           String(describing: scheme),
           String(describing: cacheKey))

    var eventTransformer: [EventTransformer] = []

    if let reverse = scheme.scrolling?.reverse {
        let vertical = reverse.vertical ?? false
        let horizontal = reverse.horizontal ?? false

        if vertical || horizontal {
            eventTransformer.append(ReverseScrolling(vertically: vertical, horizontally: horizontal))
        }
    }

    if let distance = scheme.scrolling?.distance?.horizontal {
        eventTransformer.append(LinearScrollingHorizontal(distance: distance))
    }

    if let distance = scheme.scrolling?.distance?.vertical {
        eventTransformer.append(LinearScrollingVertical(distance: distance))
    }

    if let modifiers = scheme.scrolling?.modifiers {
        eventTransformer.append(ModifierActions(modifiers: modifiers))
    }

    if let mappings = scheme.buttons?.mappings {
        eventTransformer.append(ButtonActions(mappings: mappings))
    }

    if let universalBackForward = scheme.buttons?.universalBackForward,
       universalBackForward != .none {
        eventTransformer.append(UniversalBackForward(universalBackForward: universalBackForward))
    }

    eventTransformerCache.setValue(eventTransformer, forKey: cacheKey)

    return eventTransformer
}
