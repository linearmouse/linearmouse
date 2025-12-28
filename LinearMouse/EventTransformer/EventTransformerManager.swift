// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Combine
import Defaults
import Foundation
import LRUCache
import os.log

class EventTransformerManager {
    static let shared = EventTransformerManager()
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventTransformerManager")

    @Default(.bypassEventsFromOtherApplications) var bypassEventsFromOtherApplications

    private var eventTransformerCache = LRUCache<CacheKey, EventTransformer>(countLimit: 16)
    private var activeCacheKey: CacheKey?

    struct CacheKey: Hashable {
        var deviceMatcher: DeviceMatcher?
        var pid: pid_t?
        var screen: String?
    }

    private var subscriptions = Set<AnyCancellable>()

    init() {
        ConfigurationState.shared
            .$configuration
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.eventTransformerCache.removeAllValues()
            }
            .store(in: &subscriptions)
    }

    private let sourceBundleIdentifierBypassSet: Set<String> = [
        "cc.ffitch.shottr"
    ]

    func get(
        withCGEvent cgEvent: CGEvent,
        withSourcePid sourcePid: pid_t?,
        withTargetPid targetPid: pid_t?,
        withMouseLocationPid mouseLocationPid: pid_t?,
        withDisplay display: String?
    ) -> EventTransformer {
        let prevActiveCacheKey = activeCacheKey
        defer {
            if let prevActiveCacheKey,
               prevActiveCacheKey != activeCacheKey {
                if let eventTransformer = eventTransformerCache.value(forKey: prevActiveCacheKey) as? Deactivatable {
                    eventTransformer.deactivate()
                }
                if let activeCacheKey,
                   let eventTransformer = eventTransformerCache.value(forKey: activeCacheKey) as? Deactivatable {
                    eventTransformer.reactivate()
                }
            }
        }

        activeCacheKey = nil

        if sourcePid != nil, bypassEventsFromOtherApplications {
            os_log(
                "Return noop transformer because this event is sent by %{public}s",
                log: Self.log,
                type: .info,
                sourcePid?.bundleIdentifier ?? "(unknown)"
            )
            return []
        }
        if let sourceBundleIdentifier = sourcePid?.bundleIdentifier,
           sourceBundleIdentifierBypassSet.contains(sourceBundleIdentifier) {
            os_log(
                "Return noop transformer because the source application %{public}s is in the bypass set",
                log: Self.log,
                type: .info,
                sourceBundleIdentifier
            )
            return []
        }

        let pid = mouseLocationPid ?? targetPid

        let device = DeviceManager.shared.deviceFromCGEvent(cgEvent)
        let cacheKey = CacheKey(
            deviceMatcher: device.map { DeviceMatcher(of: $0) },
            pid: pid,
            screen: display
        )
        activeCacheKey = cacheKey
        if let eventTransformer = eventTransformerCache.value(forKey: cacheKey) {
            return eventTransformer
        }

        let scheme = ConfigurationState.shared.configuration.matchScheme(
            withDevice: device,
            withPid: pid,
            withDisplay: display
        )

        // TODO: Patch EventTransformer instead of rebuilding it

        os_log(
            "Initialize EventTransformer with scheme: %{public}@ (device=%{public}@, pid=%{public}@, screen=%{public}@)",
            log: Self.log,
            type: .info,
            String(describing: scheme),
            String(describing: device),
            String(describing: pid),
            String(describing: display)
        )

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
                .append(ScrollingAccelerationSpeedAdjustmentTransformer(
                    acceleration: scheme.scrolling.acceleration,
                    speed: scheme.scrolling.speed
                ))
        }

        if let timeout = scheme.buttons.clickDebouncing.timeout, timeout > 0,
           let buttons = scheme.buttons.clickDebouncing.buttons {
            let resetTimerOnMouseUp = scheme.buttons.clickDebouncing.resetTimerOnMouseUp ?? false
            for button in buttons {
                eventTransformer.append(ClickDebouncingTransformer(
                    for: button,
                    timeout: TimeInterval(timeout) / 1000,
                    resetTimerOnMouseUp: resetTimerOnMouseUp
                ))
            }
        }

        if let modifiers = scheme.scrolling.$modifiers {
            eventTransformer.append(ModifierActionsTransformer(modifiers: modifiers))
        }

        if scheme.buttons.switchPrimaryButtonAndSecondaryButtons == true {
            eventTransformer.append(SwitchPrimaryAndSecondaryButtonsTransformer())
        }

        if let gesture = scheme.buttons.$gesture,
           gesture.enabled ?? false,
           let button = gesture.button,
           let mouseButton = CGMouseButton(rawValue: UInt32(button)) {
            eventTransformer.append(GestureButtonTransformer(
                button: mouseButton,
                threshold: Double(gesture.threshold ?? 50),
                deadZone: Double(gesture.deadZone ?? 40),
                cooldownMs: gesture.cooldownMs ?? 500,
                actions: gesture.actions
            ))
        }

        if let mappings = scheme.buttons.mappings {
            eventTransformer.append(ButtonActionsTransformer(mappings: mappings))
        }

        if let universalBackForward = scheme.buttons.universalBackForward,
           universalBackForward != .none {
            eventTransformer.append(UniversalBackForwardTransformer(universalBackForward: universalBackForward))
        }

        if let redirectsToScroll = scheme.pointer.redirectsToScroll, redirectsToScroll {
            eventTransformer.append(PointerRedirectsToScrollTransformer())
        }

        eventTransformerCache.setValue(eventTransformer, forKey: cacheKey)

        return eventTransformer
    }
}
