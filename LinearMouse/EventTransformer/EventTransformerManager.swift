// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation
import os.log

class EventTransformerManager {
    static let shared = EventTransformerManager()
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTransformerManager")

    private var lastEventTransformer: EventTransformer?
    private var lastPid: pid_t?
    private var subscriptions = Set<AnyCancellable>()

    init() {
        ConfigurationState.shared.$configuration
            .debounce(for: 0.2, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.lastEventTransformer = nil
            }
            .store(in: &subscriptions)

        DeviceManager.shared.$lastActiveDevice
            .debounce(for: 0.2, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.lastEventTransformer = nil
            }
            .store(in: &subscriptions)
    }

    func get(withPid pid: pid_t?) -> EventTransformer {
        if lastPid != pid {
            lastEventTransformer = nil
        }

        if let eventTransformer = lastEventTransformer {
            return eventTransformer
        }

        let device = DeviceManager.shared.lastActiveDevice

        let scheme = ConfigurationState.shared.configuration.matchScheme(withDevice: device,
                                                                         withPid: pid)

        // TODO: Patch EventTransformer instead of rebuilding it

        os_log("Initialize EventTransformer with scheme: %{public}@ (device=%{public}@, pid=%{public}@)",
               log: Self.log, type: .debug,
               String(describing: scheme),
               String(describing: device),
               String(describing: pid))

        var eventTransformer: [EventTransformer] = []

        if let reverse = scheme.scrolling.$reverse {
            let vertical = reverse.vertical ?? false
            let horizontal = reverse.horizontal ?? false

            if vertical || horizontal {
                eventTransformer.append(ReverseScrolling(vertically: vertical, horizontally: horizontal))
            }
        }

        if let distance = scheme.scrolling.distance.horizontal {
            eventTransformer.append(LinearScrollingHorizontal(distance: distance))
        }

        if let distance = scheme.scrolling.distance.vertical {
            eventTransformer.append(LinearScrollingVertical(distance: distance))
        }

        if scheme.scrolling.acceleration.vertical ?? 1 != 1 || scheme.scrolling.acceleration.horizontal ?? 1 != 1 ||
            scheme.scrolling.speed.vertical ?? 0 != 0 || scheme.scrolling.speed.horizontal ?? 0 != 0 {
            eventTransformer.append(ScrollingAccelerationSpeedAdjustment(acceleration: scheme.scrolling.acceleration,
                                                                         speed: scheme.scrolling.speed))
        }

        if let debounceClicks = scheme.buttons.debounceClicks, debounceClicks > 0 {
            eventTransformer.append(DebounceClicks(interval: TimeInterval(debounceClicks) / 1000))
        }

        if let modifiers = scheme.scrolling.$modifiers {
            eventTransformer.append(ModifierActions(modifiers: modifiers))
        }

        if let mappings = scheme.buttons.mappings {
            eventTransformer.append(ButtonActions(mappings: mappings))
        }

        if let universalBackForward = scheme.buttons.universalBackForward,
           universalBackForward != .none {
            eventTransformer.append(UniversalBackForward(universalBackForward: universalBackForward))
        }

        lastPid = pid
        lastEventTransformer = eventTransformer

        return eventTransformer
    }
}
