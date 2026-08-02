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

    /// Keep one transformer chain for the lifetime of a physical mouse-button
    /// stream. A drag can cross an application, display, menu bar, or overlay,
    /// all of which may otherwise select a different scheme between down and
    /// up. Switching chains mid-stream is especially unsafe when an earlier
    /// button event was buffered and replayed: the release must follow the same
    /// delivery path to remain paired with that replayed press.
    private struct ActivePointerStream {
        var buttons: Set<CGMouseButton>
        var resolution: EventTransformerResolution
    }

    private var activePointerStream: ActivePointerStream?

    struct CacheKey: Hashable {
        var deviceMatcher: DeviceMatcher?
        var process: ProcessIdentity?
        var screen: String?
    }

    private var subscriptions = Set<AnyCancellable>()

    init() {
        ConfigurationState.shared
            .$configuration
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                if EventThread.shared.performAndWait({ self.resetState() }) == nil {
                    self.resetState()
                }
            }
            .store(in: &subscriptions)
    }

    /// Called from `EventThread.onWillStop` on the event thread.
    func resetForRestart() {
        resetState()
    }

    private let sourceBundleIdentifierBypassSet: Set<String> = [
        "cc.ffitch.shottr"
    ]

    func resolve(
        withCGEvent cgEvent: CGEvent,
        withSourcePid sourcePid: pid_t?,
        withTargetPid targetPid: pid_t?,
        withMouseLocationPid mouseLocationPid: pid_t?,
        withDisplay display: String?
    ) -> EventTransformerResolution {
        if EventThread.shared.isCurrent {
            return resolveOnCurrentThread(
                withCGEvent: cgEvent,
                withSourcePid: sourcePid,
                withTargetPid: targetPid,
                withMouseLocationPid: mouseLocationPid,
                withDisplay: display
            )
        }

        if let resolution = EventThread.shared.performAndWait({
            self.resolveOnCurrentThread(
                withCGEvent: cgEvent,
                withSourcePid: sourcePid,
                withTargetPid: targetPid,
                withMouseLocationPid: mouseLocationPid,
                withDisplay: display
            )
        }) {
            return resolution
        }

        return resolveOnCurrentThread(
            withCGEvent: cgEvent,
            withSourcePid: sourcePid,
            withTargetPid: targetPid,
            withMouseLocationPid: mouseLocationPid,
            withDisplay: display
        )
    }

    func get(
        withCGEvent cgEvent: CGEvent,
        withSourcePid sourcePid: pid_t?,
        withTargetPid targetPid: pid_t?,
        withMouseLocationPid mouseLocationPid: pid_t?,
        withDisplay display: String?
    ) -> EventTransformer {
        resolve(
            withCGEvent: cgEvent,
            withSourcePid: sourcePid,
            withTargetPid: targetPid,
            withMouseLocationPid: mouseLocationPid,
            withDisplay: display
        )
        .transformer
    }

    private func resolveOnCurrentThread(
        withCGEvent cgEvent: CGEvent,
        withSourcePid sourcePid: pid_t?,
        withTargetPid targetPid: pid_t?,
        withMouseLocationPid mouseLocationPid: pid_t?,
        withDisplay display: String?
    ) -> EventTransformerResolution {
        if sourcePid != nil, bypassEventsFromOtherApplications, !cgEvent.isLinearMouseSyntheticEvent {
            os_log(
                "Return noop transformer because this event is sent by %{public}s",
                log: Self.log,
                type: .info,
                sourcePid?.bundleIdentifier ?? "(unknown)"
            )
            return .init(transformer: [], context: .init(device: nil))
        }
        if let sourceBundleIdentifier = sourcePid?.bundleIdentifier,
           sourceBundleIdentifierBypassSet.contains(sourceBundleIdentifier) {
            os_log(
                "Return noop transformer because the source application %{public}s is in the bypass set",
                log: Self.log,
                type: .info,
                sourceBundleIdentifier
            )
            return .init(transformer: [], context: .init(device: nil))
        }

        let device = DeviceManager.shared.deviceFromCGEvent(cgEvent)

        if var activePointerStream {
            updatePointerButtons(in: &activePointerStream.buttons, with: cgEvent)
            let resolution = activePointerStream.resolution
            self.activePointerStream = activePointerStream.buttons.isEmpty ? nil : activePointerStream
            return resolution
        }

        let pid = mouseLocationPid ?? targetPid
        let process = pid?.processIdentity

        let resolution = EventTransformerResolution(
            transformer: get(
                withDevice: device,
                withProcess: process,
                withDisplay: display,
                updateActiveCacheKey: true
            ),
            context: .init(device: device)
        )

        var pointerButtons = Set<CGMouseButton>()
        updatePointerButtons(in: &pointerButtons, with: cgEvent)
        if !pointerButtons.isEmpty {
            activePointerStream = .init(buttons: pointerButtons, resolution: resolution)
        }

        return resolution
    }

    private func updatePointerButtons(in buttons: inout Set<CGMouseButton>, with event: CGEvent) {
        guard let button = MouseEventView(event).mouseButton else {
            return
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            buttons.insert(button)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            buttons.remove(button)
        default:
            break
        }
    }

    func get(withDevice device: Device?, withPid pid: pid_t?, withDisplay display: String?) -> EventTransformer {
        get(withDevice: device, withProcess: pid?.processIdentity, withDisplay: display)
    }

    func get(
        withDevice device: Device?,
        withProcess process: ProcessIdentity?,
        withDisplay display: String?
    ) -> EventTransformer {
        if EventThread.shared.isCurrent {
            return getOnCurrentThread(withDevice: device, withProcess: process, withDisplay: display)
        }

        if let transformer = EventThread.shared.performAndWait({
            self.getOnCurrentThread(withDevice: device, withProcess: process, withDisplay: display)
        }) {
            return transformer
        }

        return getOnCurrentThread(withDevice: device, withProcess: process, withDisplay: display)
    }

    private func getOnCurrentThread(
        withDevice device: Device?,
        withProcess process: ProcessIdentity?,
        withDisplay display: String?
    ) -> EventTransformer {
        get(withDevice: device, withProcess: process, withDisplay: display, updateActiveCacheKey: false)
    }

    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult {
        if EventThread.shared.isCurrent {
            return handleLogitechControlEventOnCurrentThread(context)
        }

        if let result = EventThread.shared.performAndWait({
            self.handleLogitechControlEventOnCurrentThread(context)
        }) {
            return result
        }

        return handleLogitechControlEventOnCurrentThread(context)
    }

    private func handleLogitechControlEventOnCurrentThread(
        _ context: LogitechEventContext
    ) -> LogitechControlEventHandlingResult {
        let pid = ConfigurationState.shared.configuration.usesProcessConditions ? context.pid : nil
        let transformer = get(withDevice: context.device, withPid: pid, withDisplay: context.display)
        return (transformer as? LogitechControlEventHandling)?.handleLogitechControlEvent(context) ?? .notHandled
    }

    private func get(
        withDevice device: Device?,
        withProcess process: ProcessIdentity?,
        withDisplay display: String?,
        updateActiveCacheKey: Bool
    ) -> EventTransformer {
        let prevActiveCacheKey = activeCacheKey
        if updateActiveCacheKey {
            activeCacheKey = nil
        }
        defer {
            if updateActiveCacheKey,
               let prevActiveCacheKey,
               prevActiveCacheKey != activeCacheKey {
                transition(
                    from: eventTransformerCache.value(forKey: prevActiveCacheKey),
                    to: activeCacheKey.flatMap { eventTransformerCache.value(forKey: $0) }
                )
            }
        }

        let cacheKey = CacheKey(
            deviceMatcher: device.map { DeviceMatcher(of: $0) },
            process: process,
            screen: display
        )
        if updateActiveCacheKey {
            activeCacheKey = cacheKey
        }
        if let eventTransformer = eventTransformerCache.value(forKey: cacheKey) {
            return eventTransformer
        }

        let scheme = ConfigurationState.shared.configuration.matchScheme(
            withDevice: device,
            withProcess: process,
            withDisplay: display
        )

        // TODO: Patch EventTransformer instead of rebuilding it

        os_log(
            "Initialize EventTransformer with scheme: %{public}@ (device=%{public}@, pid=%{public}@, screen=%{public}@)",
            log: Self.log,
            type: .info,
            String(describing: scheme),
            String(describing: device),
            String(describing: process?.pid),
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
        let hasSmoothedScrolling = smoothed.vertical != nil || smoothed.horizontal != nil
        let buttonMappings = (scheme.buttons.mappings ?? []).map { mapping in
            var mapping = mapping
            mapping.normalizeAsStructured()
            return mapping
        }
        let gestureTransformer: GestureButtonTransformer? = if let gesture = scheme.buttons.$gesture,
                                                               gesture.enabled ?? false,
                                                               let trigger = gesture.trigger,
                                                               trigger.button != nil {
            GestureButtonTransformer(
                trigger: trigger,
                threshold: Double(gesture.threshold ?? 50),
                deadZone: Double(gesture.deadZone ?? 40),
                cooldownMs: gesture.cooldownMs ?? 500,
                actions: gesture.actions
            )
        } else {
            nil
        }
        if device != nil {
            let highResolutionWheelNormalizer = LogitechHighResolutionWheelNormalizer(
                verticalMode: highResolutionWheelNormalizerMode(
                    distance: scheme.scrolling.distance.vertical,
                    smoothed: smoothed.vertical
                ),
                horizontalMode: highResolutionWheelNormalizerMode(
                    distance: scheme.scrolling.distance.horizontal,
                    smoothed: smoothed.horizontal
                )
            )
            if highResolutionWheelNormalizer.normalizesAnyAxis {
                eventTransformer.append(highResolutionWheelNormalizer)
            }
        }

        if scheme.buttons.switchPrimaryButtonAndSecondaryButtons == true {
            eventTransformer.append(SwitchPrimaryAndSecondaryButtonsTransformer())
        }

        if !buttonMappings.isEmpty {
            eventTransformer.append(ButtonMappingTransformer(
                mappings: buttonMappings,
                universalBackForward: scheme.buttons.universalBackForward,
                gestureTransformer: gestureTransformer
            ))
        }

        // Record the normalized/reversed physical wheel before configured
        // modifier actions or smoothing can consume or reshape it.
        eventTransformer.append(ButtonMappingScrollRecordingTransformer())

        if let modifiers = scheme.scrolling.$modifiers,
           hasSmoothedScrolling {
            eventTransformer.append(ModifierActionsTransformer(modifiers: modifiers))
        }

        if hasSmoothedScrolling {
            eventTransformer.append(SmoothedScrollingTransformer(
                smoothed: smoothed
            ))
        }

        if let distance = scheme.scrolling.distance.horizontal {
            if smoothed.horizontal == nil {
                eventTransformer.append(LinearScrollingHorizontalTransformer(
                    distance: distance
                ))
            }
        }

        if let distance = scheme.scrolling.distance.vertical {
            if smoothed.vertical == nil {
                eventTransformer.append(LinearScrollingVerticalTransformer(
                    distance: distance
                ))
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

        if let timeout = scheme.buttons.clickDebouncing.timeout, timeout > 0 {
            let mode = scheme.buttons.clickDebouncing.mode ?? .legacy
            let resetTimerOnMouseUp = scheme.buttons.clickDebouncing.resetTimerOnMouseUp ?? false
            let buttons = mode == .libinput
                ? Scheme.Buttons.ClickDebouncing.standardButtons
                : scheme.buttons.clickDebouncing.buttons ?? []

            for button in buttons {
                switch mode {
                case .legacy:
                    eventTransformer.append(ClickDebouncingTransformer(
                        for: button,
                        timeout: TimeInterval(timeout) / 1000,
                        resetTimerOnMouseUp: resetTimerOnMouseUp
                    ))
                case .libinput:
                    eventTransformer.append(LibinputClickDebouncingTransformer(
                        for: button
                    ))
                }
            }
        }

        if let modifiers = scheme.scrolling.$modifiers,
           !hasSmoothedScrolling {
            eventTransformer.append(ModifierActionsTransformer(modifiers: modifiers))
        }

        if let autoScrollTransformer = autoScrollTransformer(for: scheme.buttons.$autoScroll) {
            eventTransformer.append(autoScrollTransformer)
        }

        if buttonMappings.isEmpty, let gestureTransformer {
            eventTransformer.append(gestureTransformer)
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

    private func highResolutionWheelNormalizerMode(
        distance: Scheme.Scrolling.Distance?,
        smoothed: Scheme.Scrolling.Smoothed?
    ) -> LogitechHighResolutionWheelNormalizer.AxisMode {
        if smoothed != nil {
            return .passthrough
        }

        switch distance {
        case .some(.line), .some(.pixel):
            return .passthrough
        case .some(.auto), nil:
            return .lowResolution
        }
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

        if let sharedAutoScrollTransformer,
           sharedAutoScrollTransformer.matchesConfiguration(
               trigger: trigger,
               modes: modes,
               speed: speed
           ) {
            return sharedAutoScrollTransformer
        }

        sharedAutoScrollTransformer?.deactivate()
        sharedAutoScrollTransformer = nil
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: modes,
            speed: speed
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

    private func resetState() {
        let activeEventTransformer = activeCacheKey.flatMap { eventTransformerCache.value(forKey: $0) }
        let oldAutoScroll = sharedAutoScrollTransformer
        deactivate(activeEventTransformer, excluding: oldAutoScroll)
        sharedAutoScrollTransformer = nil
        activePointerStream = nil
        activeCacheKey = nil
        eventTransformerCache.removeAllValues()
        oldAutoScroll?.deactivate()
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

final class ButtonMappingScrollRecordingTransformer: EventTransformer {
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard SettingsState.shared.recording,
              let recordingSessionID = SettingsState.shared.buttonMappingRecordingSessionID,
              event.type == .scrollWheel,
              !event.isLinearMouseSyntheticEvent,
              let scroll = Self.scrollDirection(of: event) else {
            return event
        }

        let modifierFlags = event.flags
        DispatchQueue.main.async {
            guard SettingsState.shared.isCurrentButtonMappingRecordingSession(recordingSessionID) else {
                return
            }

            SettingsState.shared.recordedButtonMappingEvent = .init(
                recordingSessionID: recordingSessionID,
                button: nil,
                scroll: scroll,
                modifierFlags: modifierFlags
            )
        }

        return nil
    }

    private static func scrollDirection(of event: CGEvent) -> Scheme.Buttons.Mapping.ScrollDirection? {
        let view = ScrollWheelEventView(event)
        if view.deltaYSignum < 0 {
            return .down
        }
        if view.deltaYSignum > 0 {
            return .up
        }
        if view.deltaXSignum < 0 {
            return .right
        }
        if view.deltaXSignum > 0 {
            return .left
        }
        return nil
    }
}
