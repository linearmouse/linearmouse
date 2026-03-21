// MIT License
// Copyright (c) 2021-2026 LinearMouse

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
    private var sharedAutoScrollTransformer: AutoScrollTransformer?

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
                self?.sharedAutoScrollTransformer?.deactivate()
                self?.sharedAutoScrollTransformer = nil
                self?.activeCacheKey = nil
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
                transition(
                    from: eventTransformerCache.value(forKey: prevActiveCacheKey),
                    to: activeCacheKey.flatMap { eventTransformerCache.value(forKey: $0) }
                )
            }
        }

        activeCacheKey = nil

        if sourcePid != nil, bypassEventsFromOtherApplications, !cgEvent.isLinearMouseSyntheticEvent {
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

        let smoothed = Scheme.Scrolling.Bidirectional(
            vertical: scheme.scrolling.smoothed.vertical?.isEnabled == true ? scheme.scrolling.smoothed.vertical : nil,
            horizontal: scheme.scrolling.smoothed.horizontal?.isEnabled == true ? scheme.scrolling.smoothed
                .horizontal : nil
        )

        if smoothed.vertical != nil || smoothed.horizontal != nil {
            eventTransformer.append(SmoothedScrollingTransformer(smoothed: smoothed))
        }

        if let distance = scheme.scrolling.distance.horizontal {
            if smoothed.horizontal == nil {
                eventTransformer.append(LinearScrollingHorizontalTransformer(distance: distance))
            }
        }

        if let distance = scheme.scrolling.distance.vertical {
            if smoothed.vertical == nil {
                eventTransformer.append(LinearScrollingVerticalTransformer(distance: distance))
            }
        }

        let acceleration = Scheme.Scrolling.Bidirectional<Decimal>(
            vertical: smoothed.vertical == nil ? scheme.scrolling.acceleration.vertical : nil,
            horizontal: smoothed.horizontal == nil ? scheme.scrolling.acceleration.horizontal : nil
        )
        let speed = Scheme.Scrolling.Bidirectional<Decimal>(
            vertical: smoothed.vertical == nil ? scheme.scrolling.speed.vertical : nil,
            horizontal: smoothed.horizontal == nil ? scheme.scrolling.speed.horizontal : nil
        )

        if acceleration.vertical ?? 1 != 1 || acceleration.horizontal ?? 1 != 1 ||
            speed.vertical ?? 0 != 0 || speed.horizontal ?? 0 != 0 {
            eventTransformer
                .append(ScrollingAccelerationSpeedAdjustmentTransformer(
                    acceleration: acceleration,
                    speed: speed
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

        if let autoScrollTransformer = autoScrollTransformer(for: scheme.buttons.$autoScroll) {
            eventTransformer.append(autoScrollTransformer)
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

    private func autoScrollTransformer(for autoScroll: Scheme.Buttons.AutoScroll?) -> AutoScrollTransformer? {
        if let sharedAutoScrollTransformer, sharedAutoScrollTransformer.isAutoscrollActive {
            return sharedAutoScrollTransformer
        }

        guard let autoScroll,
              autoScroll.enabled ?? false,
              let trigger = autoScroll.trigger,
              trigger.valid else {
            sharedAutoScrollTransformer?.deactivate()
            sharedAutoScrollTransformer = nil
            return nil
        }

        let modes = autoScroll.normalizedModes
        let speed = autoScroll.speed?.asTruncatedDouble ?? 1
        let preserveNativeMiddleClick = autoScroll.preserveNativeMiddleClick ?? true

        if let sharedAutoScrollTransformer,
           sharedAutoScrollTransformer.matchesConfiguration(
               trigger: trigger,
               modes: modes,
               speed: speed,
               preserveNativeMiddleClick: preserveNativeMiddleClick
           ) {
            return sharedAutoScrollTransformer
        }

        sharedAutoScrollTransformer?.deactivate()
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: modes,
            speed: speed,
            preserveNativeMiddleClick: preserveNativeMiddleClick
        )
        sharedAutoScrollTransformer = transformer
        return transformer
    }

    private func transition(from previous: EventTransformer?, to current: EventTransformer?) {
        let preservedAutoScrollTransformer = sharedAutoScrollTransformer?.isAutoscrollActive == true
            ? sharedAutoScrollTransformer
            : nil

        deactivate(previous, excluding: preservedAutoScrollTransformer)
        reactivate(current, excluding: preservedAutoScrollTransformer)
    }

    private func deactivate(
        _ transformer: EventTransformer?,
        excluding preservedAutoScrollTransformer: AutoScrollTransformer?
    ) {
        guard let transformer else {
            return
        }

        if let transformers = transformer as? [EventTransformer] {
            for transformer in transformers {
                if let preservedAutoScrollTransformer,
                   let autoScrollTransformer = transformer as? AutoScrollTransformer,
                   autoScrollTransformer === preservedAutoScrollTransformer {
                    continue
                }

                (transformer as? Deactivatable)?.deactivate()
            }
            return
        }

        if let preservedAutoScrollTransformer,
           let autoScrollTransformer = transformer as? AutoScrollTransformer,
           autoScrollTransformer === preservedAutoScrollTransformer {
            return
        }

        (transformer as? Deactivatable)?.deactivate()
    }

    private func reactivate(
        _ transformer: EventTransformer?,
        excluding preservedAutoScrollTransformer: AutoScrollTransformer?
    ) {
        guard let transformer else {
            return
        }

        if let transformers = transformer as? [EventTransformer] {
            for transformer in transformers {
                if let preservedAutoScrollTransformer,
                   let autoScrollTransformer = transformer as? AutoScrollTransformer,
                   autoScrollTransformer === preservedAutoScrollTransformer {
                    continue
                }

                (transformer as? Deactivatable)?.reactivate()
            }
            return
        }

        if let preservedAutoScrollTransformer,
           let autoScrollTransformer = transformer as? AutoScrollTransformer,
           autoScrollTransformer === preservedAutoScrollTransformer {
            return
        }

        (transformer as? Deactivatable)?.reactivate()
    }
}
