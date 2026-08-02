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

    private final class TransformerRoute {
        let id = UUID()
        let transformer: EventTransformer

        init(transformer: EventTransformer) {
            self.transformer = transformer
        }
    }

    private var eventTransformerCache = LRUCache<CacheKey, TransformerRoute>(countLimit: 16)
    private var activeRoute: TransformerRoute?
    private var retiredRoutes = [UUID: TransformerRoute]()
    private var sharedAutoScrollTransformer: AutoScrollTransformer?

    /// A stateful transformer remains alive until the interaction it claimed
    /// has fully drained. It is injected into the newest matching route so the
    /// rest of the Scheme can switch immediately without losing the release.
    private struct ActiveInteraction {
        var route: TransformerRoute
        var transformer: EventTransformer
        var selection: RouteSelection
    }

    private enum InteractionKey: Hashable {
        case device(Int32)
        case unidentified
    }

    private var activeInteractions = [InteractionKey: ActiveInteraction]()

    private struct RouteSelection {
        var device: Device?
        var process: ProcessIdentity?
        var display: String?

        var interactionKey: InteractionKey {
            device.map { .device($0.id) } ?? .unidentified
        }

        func mergingDevice(from previous: Self?) -> Self {
            guard device == nil, let previousDevice = previous?.device else {
                return self
            }

            return .init(
                device: previousDevice,
                process: process,
                display: display
            )
        }
    }

    struct CacheKey: Hashable {
        var deviceID: Int32?
        var deviceMatcher: DeviceMatcher?
        var process: ProcessIdentity?
        var screen: String?

        init(
            deviceID: Int32? = nil,
            deviceMatcher: DeviceMatcher?,
            process: ProcessIdentity?,
            screen: String?
        ) {
            self.deviceID = deviceID
            self.deviceMatcher = deviceMatcher
            self.process = process
            self.screen = screen
        }
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

                if EventThread.shared.performAndWait({ self.invalidateConfigurationState() }) == nil {
                    self.invalidateConfigurationState()
                }
            }
            .store(in: &subscriptions)
    }

    /// Called from `EventThread.onWillStop` on the event thread.
    func resetForRestart() {
        forceResetState()
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
        let device = DeviceManager.shared.deviceFromCGEvent(cgEvent)
        let pid = mouseLocationPid ?? targetPid
        let selection = RouteSelection(
            device: device,
            process: pid?.processIdentity,
            display: display
        )

        let activeInteraction = activeInteraction(
            for: selection,
            allowsUnidentifiedOwnerForIdentifiedSelection: isInteractionContinuation(cgEvent)
        )
        let effectiveSelection = selection.mergingDevice(from: activeInteraction?.1.selection)

        if sourcePid != nil, bypassEventsFromOtherApplications, !cgEvent.isLinearMouseSyntheticEvent {
            if let (interactionKey, interaction) = activeInteraction {
                // The owner must still receive its release even when the event
                // source would normally bypass LinearMouse. Use its original
                // route for this exceptional event so its preprocessing stays
                // identical to the accepted press.
                return drainingResolution(
                    transformer: interaction.route.transformer,
                    interaction: interaction,
                    selection: effectiveSelection,
                    interactionKey: interactionKey
                )
            }
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
            if let (interactionKey, interaction) = activeInteraction {
                return drainingResolution(
                    transformer: interaction.route.transformer,
                    interaction: interaction,
                    selection: effectiveSelection,
                    interactionKey: interactionKey
                )
            }
            os_log(
                "Return noop transformer because the source application %{public}s is in the bypass set",
                log: Self.log,
                type: .info,
                sourceBundleIdentifier
            )
            return .init(transformer: [], context: .init(device: nil))
        }

        let route = getRoute(
            withDevice: effectiveSelection.device,
            withProcess: effectiveSelection.process,
            withDisplay: effectiveSelection.display,
            updateActiveRoute: true
        )
        if let (interactionKey, interaction) = activeInteraction {
            return drainingResolution(
                transformer: transformer(
                    in: route,
                    replacingInteractionTrackersWith: interaction.transformer
                ),
                interaction: interaction,
                selection: effectiveSelection,
                interactionKey: interactionKey
            )
        }
        return resolution(for: route, selection: selection)
    }

    private func resolution(
        for route: TransformerRoute,
        selection: RouteSelection
    ) -> EventTransformerResolution {
        EventTransformerResolution(
            transformer: route.transformer,
            context: .init(device: selection.device)
        ) { [weak self] in
            self?.didProcessRoute(
                on: route,
                selection: selection,
                interactionKey: selection.interactionKey
            )
        }
    }

    private func drainingResolution(
        transformer: EventTransformer,
        interaction: ActiveInteraction,
        selection: RouteSelection,
        interactionKey: InteractionKey
    ) -> EventTransformerResolution {
        EventTransformerResolution(
            transformer: transformer,
            context: .init(device: selection.device)
        ) { [weak self] in
            self?.didProcessOwnedInteraction(
                interaction,
                selection: selection,
                interactionKey: interactionKey
            )
        }
    }

    private func didProcessRoute(
        on route: TransformerRoute,
        selection: RouteSelection,
        interactionKey: InteractionKey
    ) {
        guard let transformer = activeInteractionTransformers(in: route.transformer).first else {
            return
        }
        activeInteractions[interactionKey] = .init(
            route: route,
            transformer: transformer,
            selection: selection
        )
    }

    private func didProcessOwnedInteraction(
        _ interaction: ActiveInteraction,
        selection: RouteSelection,
        interactionKey: InteractionKey
    ) {
        guard let current = activeInteractions[interactionKey],
              sameTransformer(current.transformer, interaction.transformer) else {
            return
        }

        guard hasActiveInteraction(in: interaction.transformer) else {
            activeInteractions[interactionKey] = nil
            deactivateRetiredRouteIfIdle(interaction.route)
            return
        }

        var updated = current
        updated.selection = selection
        let updatedKey = selection.interactionKey
        if interactionKey == .unidentified,
           updatedKey != .unidentified,
           activeInteractions[updatedKey] == nil {
            activeInteractions[interactionKey] = nil
            activeInteractions[updatedKey] = updated
        } else {
            activeInteractions[interactionKey] = updated
        }
    }

    private func activeInteraction(
        for selection: RouteSelection,
        allowsUnidentifiedOwnerForIdentifiedSelection: Bool = false
    ) -> (InteractionKey, ActiveInteraction)? {
        let interactionKey = selection.interactionKey
        if let interaction = activeInteractions[interactionKey] {
            return (interactionKey, interaction)
        }

        // Device metadata can be absent on a release or appear only after the
        // press. Prefer the unidentified lease in the latter case. In the
        // former, fall back only when exactly one device owns an interaction,
        // avoiding cross-routing when two mice are active simultaneously.
        if allowsUnidentifiedOwnerForIdentifiedSelection,
           interactionKey != .unidentified,
           let interaction = activeInteractions[.unidentified] {
            return (.unidentified, interaction)
        }

        guard interactionKey == .unidentified,
              activeInteractions.count == 1,
              let entry = activeInteractions.first else {
            return nil
        }
        return entry
    }

    private func isInteractionContinuation(_ event: CGEvent) -> Bool {
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }

    private func activeInteractionTransformers(in transformer: EventTransformer) -> [EventTransformer] {
        if let tracker = transformer as? EventTransformerInteractionTracking,
           tracker.hasActiveInteraction {
            return [transformer]
        }

        return (transformer as? [EventTransformer])?.flatMap {
            activeInteractionTransformers(in: $0)
        } ?? []
    }

    private func sameTransformer(_ lhs: EventTransformer, _ rhs: EventTransformer) -> Bool {
        (lhs as AnyObject) === (rhs as AnyObject)
    }

    private func transformer(
        in route: TransformerRoute,
        replacingInteractionTrackersWith owner: EventTransformer
    ) -> EventTransformer {
        guard let transformers = route.transformer as? [EventTransformer] else {
            return owner
        }

        if transformers.contains(where: { sameTransformer($0, owner) }) {
            return route.transformer
        }

        var result = [EventTransformer]()
        var insertedOwner = false
        for transformer in transformers {
            if transformer is EventTransformerInteractionTracking {
                if !insertedOwner {
                    result.append(owner)
                    insertedOwner = true
                }
                continue
            }
            result.append(transformer)
        }

        if !insertedOwner {
            let insertionIndex = result.firstIndex { $0 is ButtonMappingScrollRecordingTransformer }
                ?? result.endIndex
            result.insert(owner, at: insertionIndex)
        }
        return result
    }

    private func hasActiveInteraction(in transformer: EventTransformer) -> Bool {
        if let tracker = transformer as? EventTransformerInteractionTracking,
           tracker.hasActiveInteraction {
            return true
        }

        return (transformer as? [EventTransformer])?.contains {
            hasActiveInteraction(in: $0)
        } == true
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
        getRoute(
            withDevice: device,
            withProcess: process,
            withDisplay: display,
            updateActiveRoute: false
        ).transformer
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

    /// Abandons a diverted Logitech control stream that cannot deliver its
    /// physical release, such as when a receiver reconnect forces its monitor
    /// to restart. Cancellation must not resolve a pending short press.
    @discardableResult
    func cancelLogitechControlInteraction(_ context: LogitechEventContext) -> Bool {
        if EventThread.shared.isCurrent {
            return cancelLogitechControlInteractionOnCurrentThread(context)
        }

        if let canceled = EventThread.shared.performAndWait({
            self.cancelLogitechControlInteractionOnCurrentThread(context)
        }) {
            return canceled
        }

        return cancelLogitechControlInteractionOnCurrentThread(context)
    }

    private func cancelLogitechControlInteractionOnCurrentThread(_ context: LogitechEventContext) -> Bool {
        let pid = ConfigurationState.shared.configuration.usesProcessConditions ? context.pid : nil
        let selection = RouteSelection(
            device: context.device,
            process: pid?.processIdentity,
            display: context.display
        )
        var canceled = sharedAutoScrollTransformer?.cancelLogitechControlInteraction(context) == true

        guard let (interactionKey, interaction) = activeInteraction(
            for: selection,
            allowsUnidentifiedOwnerForIdentifiedSelection: true
        ),
            let canceler = interaction.transformer as? LogitechControlInteractionCanceling else {
            return canceled
        }

        if canceler.cancelLogitechControlInteraction(context) {
            canceled = true
            didProcessOwnedInteraction(
                interaction,
                selection: selection.mergingDevice(from: interaction.selection),
                interactionKey: interactionKey
            )
        }
        return canceled
    }

    private func handleLogitechControlEventOnCurrentThread(
        _ context: LogitechEventContext
    ) -> LogitechControlEventHandlingResult {
        let pid = ConfigurationState.shared.configuration.usesProcessConditions ? context.pid : nil
        let selection = RouteSelection(
            device: context.device,
            process: pid?.processIdentity,
            display: context.display
        )
        let interaction = activeInteraction(
            for: selection,
            allowsUnidentifiedOwnerForIdentifiedSelection: true
        )
        let effectiveSelection = selection.mergingDevice(from: interaction?.1.selection)
        if let (interactionKey, activeInteraction) = interaction {
            if !context.isPressed {
                let ownerResult = (activeInteraction.transformer as? LogitechControlEventHandling)?
                    .handleLogitechControlEvent(context) ?? .notHandled
                didProcessOwnedInteraction(
                    activeInteraction,
                    selection: effectiveSelection,
                    interactionKey: interactionKey
                )
                if ownerResult != .notHandled {
                    return ownerResult
                }

                // The release belonged to another high-priority feature (most
                // notably Auto Scroll) while this device also had a mapping
                // interaction in flight. Do not offer an unmatched release to
                // a fresh stateful recognizer.
                let route = getRoute(
                    withDevice: effectiveSelection.device,
                    withProcess: effectiveSelection.process,
                    withDisplay: effectiveSelection.display,
                    updateActiveRoute: true
                )
                return (transformerWithoutInteractionTrackers(in: route) as? LogitechControlEventHandling)?
                    .handleLogitechControlEvent(context) ?? .notHandled
            }

            let route = getRoute(
                withDevice: effectiveSelection.device,
                withProcess: effectiveSelection.process,
                withDisplay: effectiveSelection.display,
                updateActiveRoute: true
            )
            let result = (transformer(
                in: route,
                replacingInteractionTrackersWith: activeInteraction.transformer
            ) as? LogitechControlEventHandling)?.handleLogitechControlEvent(context) ?? .notHandled
            didProcessOwnedInteraction(
                activeInteraction,
                selection: effectiveSelection,
                interactionKey: interactionKey
            )
            return result
        }

        let route = getRoute(
            withDevice: effectiveSelection.device,
            withProcess: effectiveSelection.process,
            withDisplay: effectiveSelection.display,
            updateActiveRoute: true
        )
        let result = (route.transformer as? LogitechControlEventHandling)?
            .handleLogitechControlEvent(context) ?? .notHandled
        didProcessRoute(
            on: route,
            selection: effectiveSelection,
            interactionKey: effectiveSelection.interactionKey
        )
        return result
    }

    private func transformerWithoutInteractionTrackers(in route: TransformerRoute) -> EventTransformer {
        guard let transformers = route.transformer as? [EventTransformer] else {
            return route.transformer is EventTransformerInteractionTracking ? [] : route.transformer
        }
        return transformers.filter { !($0 is EventTransformerInteractionTracking) }
    }

    private func getRoute(
        withDevice device: Device?,
        withProcess process: ProcessIdentity?,
        withDisplay display: String?,
        updateActiveRoute: Bool
    ) -> TransformerRoute {
        let previousRoute = activeRoute
        if updateActiveRoute {
            activeRoute = nil
        }
        defer {
            if updateActiveRoute, previousRoute?.id != activeRoute?.id {
                transition(from: previousRoute, to: activeRoute)
            }
        }

        let cacheKey = CacheKey(
            deviceID: device?.id,
            deviceMatcher: device.map { DeviceMatcher(of: $0) },
            process: process,
            screen: display
        )
        if let route = eventTransformerCache.value(forKey: cacheKey) {
            if updateActiveRoute {
                activeRoute = route
            }
            return route
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
        let autoScrollTransformer = autoScrollTransformer(for: scheme.buttons.$autoScroll)
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

        // Auto Scroll owns its configured trigger before every other button
        // recognizer, regardless of which other button features are enabled.
        if let autoScrollTransformer {
            eventTransformer.append(autoScrollTransformer)
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

        let route = TransformerRoute(transformer: eventTransformer)
        eventTransformerCache.setValue(route, forKey: cacheKey)
        if updateActiveRoute {
            activeRoute = route
        }

        return route
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

    private func transition(from previous: TransformerRoute?, to current: TransformerRoute?) {
        let preservedAutoScrollTransformer = sharedAutoScrollTransformer?.isAutoscrollActive == true
            ? sharedAutoScrollTransformer
            : nil

        if let previous {
            if isRouteOwned(previous) || hasActiveInteraction(in: previous.transformer) {
                retiredRoutes[previous.id] = previous
                deactivate(
                    previous.transformer,
                    excluding: preservedAutoScrollTransformer,
                    interactionTransformers: preservedInteractionTransformers(in: previous)
                )
            } else {
                deactivate(previous.transformer, excluding: preservedAutoScrollTransformer)
            }
        }

        if let current {
            retiredRoutes[current.id] = nil
        }
        reactivate(current?.transformer, excluding: preservedAutoScrollTransformer)
    }

    private func isRouteOwned(_ route: TransformerRoute) -> Bool {
        activeInteractions.values.contains { $0.route.id == route.id }
    }

    private func preservedInteractionTransformers(in route: TransformerRoute) -> [EventTransformer] {
        let owned = activeInteractions.values
            .filter { $0.route.id == route.id }
            .map(\.transformer)
        return owned + activeInteractionTransformers(in: route.transformer)
    }

    private func deactivateRetiredRouteIfIdle(_ route: TransformerRoute) {
        guard retiredRoutes[route.id] != nil,
              !isRouteOwned(route),
              !hasActiveInteraction(in: route.transformer) else {
            return
        }

        retiredRoutes[route.id] = nil
        let preservedAutoScrollTransformer = sharedAutoScrollTransformer?.isAutoscrollActive == true
            ? sharedAutoScrollTransformer
            : nil
        deactivate(route.transformer, excluding: preservedAutoScrollTransformer)
    }

    private func invalidateConfigurationState() {
        let oldAutoScroll = sharedAutoScrollTransformer
        let preservedAutoScrollTransformer = oldAutoScroll?.isAutoscrollActive == true
            ? oldAutoScroll
            : nil

        if let activeRoute {
            if isRouteOwned(activeRoute) || hasActiveInteraction(in: activeRoute.transformer) {
                retiredRoutes[activeRoute.id] = activeRoute
                deactivate(
                    activeRoute.transformer,
                    excluding: oldAutoScroll,
                    interactionTransformers: preservedInteractionTransformers(in: activeRoute)
                )
            } else {
                deactivate(activeRoute.transformer, excluding: oldAutoScroll)
            }
        }

        let inactiveRetiredRoutes = retiredRoutes.values.filter {
            !isRouteOwned($0) && !hasActiveInteraction(in: $0.transformer)
        }
        for route in inactiveRetiredRoutes {
            deactivate(route.transformer, excluding: oldAutoScroll)
            retiredRoutes[route.id] = nil
        }

        activeRoute = nil
        eventTransformerCache.removeAllValues()

        if preservedAutoScrollTransformer == nil {
            sharedAutoScrollTransformer = nil
            oldAutoScroll?.deactivate()
        }
    }

    private func forceResetState() {
        let oldAutoScroll = sharedAutoScrollTransformer
        var routesByID = [UUID: TransformerRoute]()
        if let activeRoute {
            routesByID[activeRoute.id] = activeRoute
        }
        for interaction in activeInteractions.values {
            routesByID[interaction.route.id] = interaction.route
        }
        for route in retiredRoutes.values {
            routesByID[route.id] = route
        }
        for route in routesByID.values {
            deactivate(route.transformer, excluding: oldAutoScroll)
        }

        sharedAutoScrollTransformer = nil
        activeInteractions.removeAll()
        activeRoute = nil
        eventTransformerCache.removeAllValues()
        retiredRoutes.removeAll()
        oldAutoScroll?.deactivate()
    }

    private func deactivate(
        _ transformer: EventTransformer?,
        excluding preservedAutoScrollTransformer: AutoScrollTransformer?,
        interactionTransformers: [EventTransformer] = []
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
                if interactionTransformers.contains(where: { sameTransformer($0, transformer) }) {
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
        if interactionTransformers.contains(where: { sameTransformer($0, transformer) }) {
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
