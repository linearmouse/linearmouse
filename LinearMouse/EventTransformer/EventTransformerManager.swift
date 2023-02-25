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

    private let sourceBundleIdentifierBypassSet: Set<String> = [
        "cc.ffitch.shottr"
    ]

    func get(withSourcePid sourcePid: pid_t?, withTargetPid pid: pid_t?) -> EventTransformer {
        if let sourceBundleIdentifier = sourcePid?.bundleIdentifier,
           sourceBundleIdentifierBypassSet.contains(sourceBundleIdentifier) {
            os_log("Return noop transformer because the source application %{public}s is in the bypass set",
                   log: Self.log, type: .debug,
                   sourceBundleIdentifier)
            return []
        }

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
                eventTransformer.append(ReverseScrollingTransformer(vertically: vertical, horizontally: horizontal))
            }
        }

        if let distance = scheme.scrolling.distance.horizontal {
            eventTransformer.append(LinearScrollingHorizontalTransformer(distance: distance))
        }

        if let distance = scheme.scrolling.distance.vertical {
            eventTransformer.append(LinearScrollingVerticalTransformer(distance: distance))
        }

        if scheme.scrolling.acceleration.vertical ?? 1 != 1 || scheme.scrolling.acceleration.horizontal ?? 1 != 1 ||
            scheme.scrolling.speed.vertical ?? 0 != 0 || scheme.scrolling.speed.horizontal ?? 0 != 0 {
            eventTransformer
                .append(ScrollingAccelerationSpeedAdjustmentTransformer(acceleration: scheme.scrolling.acceleration,
                                                                        speed: scheme.scrolling.speed))
        }

        if let timeout = scheme.buttons.clickDebouncing.timeout, timeout > 0,
           let buttons = scheme.buttons.clickDebouncing.buttons {
            let resetTimerOnMouseUp = scheme.buttons.clickDebouncing.resetTimerOnMouseUp ?? false
            for button in buttons {
                eventTransformer.append(ClickDebouncingTransformer(for: button,
                                                                   timeout: TimeInterval(timeout) / 1000,
                                                                   resetTimerOnMouseUp: resetTimerOnMouseUp))
            }
        }

        if let modifiers = scheme.scrolling.$modifiers {
            eventTransformer.append(ModifierActionsTransformer(modifiers: modifiers))
        }

        if let mappings = scheme.buttons.mappings {
            eventTransformer.append(ButtonActionsTransformer(mappings: mappings))
        }

        if let universalBackForward = scheme.buttons.universalBackForward,
           universalBackForward != .none {
            eventTransformer.append(UniversalBackForwardTransformer(universalBackForward: universalBackForward))
        }

        lastPid = pid
        lastEventTransformer = eventTransformer

        return eventTransformer
    }
}
