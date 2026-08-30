// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP

final class LogitechDeviceSession {
    /// Hardware target invariants:
    /// 1. A TargetLease is immutable and binds one operation to its token, route,
    ///    stable target key, and receiver slot.
    /// 2. A feature result may mutate session state only while that exact lease
    ///    still belongs to the current route and cancellation token.
    /// 3. A process-store handle may be attached or consumed only for the stable
    ///    target carried by the validated lease.
    /// 4. A stable receiver baseline is quarantined while identity is incomplete,
    ///    may rebind to the same serial (even in another slot), and is discarded
    ///    when a different serial is confirmed.
    /// 5. A receiver baseline without a stable key never crosses route loss.
    /// 6. Promotion copies the session's saved original mode; it never rereads
    ///    managed hardware or substitutes a later write's previous mode.
    struct TargetLease {
        let route: LogitechReceiverRoute?
        let stableTargetKey: LogitechHardwareTargetKey?
        let receiverSlot: UInt8?
        fileprivate let token: CancellationToken
    }

    struct FeatureBinding<Feature> {
        let feature: Feature
        let stableTargetKey: LogitechHardwareTargetKey?
        let receiverSlot: UInt8?
    }

    struct FeatureAccess<Feature> {
        let feature: Feature
        let lease: TargetLease

        fileprivate var token: CancellationToken {
            lease.token
        }
    }

    fileprivate final class InitialHiResWheelState {
        var lease: TargetLease
        var enabled: Bool
        var baselineHandle: LogitechHardwareBaselineStore.HiResHandle?

        init(
            lease: TargetLease,
            enabled: Bool,
            baselineHandle: LogitechHardwareBaselineStore.HiResHandle?
        ) {
            self.lease = lease
            self.enabled = enabled
            self.baselineHandle = baselineHandle
        }
    }

    struct HiResBaselinePromotion {
        let enabled: Bool
        let target: LogitechHardwareTargetKey
        fileprivate let initialState: InitialHiResWheelState
        fileprivate let currentLease: TargetLease
    }

    enum HiResWheelCommit {
        case committed(LogitechHardwareBaselineStore.HiResHandle?)
        case rejected
    }

    private struct State {
        var discovery: LogitechReceiverDiscovery?
        var adjustableDPI: FeatureAccess<AdjustableDPI>?
        var hiResWheel: FeatureAccess<HiResWheel>?
        var dpiCancellationSource = CancellationSource()
        var hiResWheelCancellationSource = CancellationSource()
        var sensorDPI: Int?
        var hiResWheelEnabled: Bool?
        var hiResWheelMultiplier: Int?
        var initialHiResWheelState: InitialHiResWheelState?
        var hiResWheelRestoreRetryNeeded = false
    }

    struct DiscoveryUpdate {
        let hardwareTargetChanged: Bool
        let candidateAvailabilityChanged: Bool
        let hasCandidates: Bool
    }

    private let queue: DispatchQueue
    private let queueContext = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var state = State()

    private let dpiApplyCoordinator: HardwareSettingApplyCoordinator
    private let hiResWheelApplyCoordinator: HardwareSettingApplyCoordinator

    init(deviceID: Int32) {
        queue = DispatchQueue(
            label: "app.linearmouse.logitech-settings.\(deviceID)",
            qos: .default
        )
        dpiApplyCoordinator = Self.makeApplyCoordinator(queue: queue)
        hiResWheelApplyCoordinator = Self.makeApplyCoordinator(queue: queue)
        queue.setSpecific(key: queueContext, value: ())
    }

    private func withState<T>(_ body: (inout State) throws -> T) rethrows -> T {
        try lock.withLock { try body(&state) }
    }

    var discoverySnapshot: LogitechReceiverDiscovery? {
        withState { $0.discovery }
    }

    var sensorDPI: Int? {
        withState { $0.sensorDPI }
    }

    var hiResWheelEnabled: Bool? {
        withState { $0.hiResWheelEnabled }
    }

    var hiResWheelNormalizationMultiplier: Int? {
        withState { state in
            guard state.hiResWheelEnabled == true,
                  let multiplier = state.hiResWheelMultiplier,
                  multiplier > 1 else {
                return nil
            }
            return multiplier
        }
    }

    func perform(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    func performSynchronously<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueContext) != nil {
            return try work()
        }
        return try queue.sync(execute: work)
    }

    func updateDiscovery(_ discovery: LogitechReceiverDiscovery?) -> DiscoveryUpdate {
        let dpiCoordinator = dpiApplyCoordinator
        let wheelCoordinator = hiResWheelApplyCoordinator
        let update = withState { state -> (DiscoveryUpdate, CancellationSource?, CancellationSource?) in
            let previousDiscovery = state.discovery
            let previousRoute = previousDiscovery?.route
            let currentRoute = discovery?.route
            let routeIdentityChanged = previousRoute != currentRoute
            var hardwareTargetChanged = !Self.routeCanContinue(from: previousRoute, to: currentRoute)
            let candidateAvailabilityChanged = previousDiscovery?.identities.isEmpty
                != discovery?.identities.isEmpty

            let previousInitialStateUsable = state.initialHiResWheelState.map {
                Self.initialStateRelation($0, to: previousRoute) == .compatible
            } ?? false
            state.discovery = discovery

            if currentRoute == nil,
               let initialState = state.initialHiResWheelState,
               initialState.lease.route != nil,
               initialState.lease.stableTargetKey == nil {
                state.initialHiResWheelState = nil
            }

            var stableInitialToRebind: InitialHiResWheelState?
            if let initialState = state.initialHiResWheelState, let currentRoute {
                switch Self.initialStateRelation(initialState, to: currentRoute) {
                case .different:
                    state.initialHiResWheelState = nil
                    hardwareTargetChanged = true
                case .compatible:
                    if initialState.lease.stableTargetKey != nil {
                        stableInitialToRebind = initialState
                    }
                    if !previousInitialStateUsable {
                        hardwareTargetChanged = true
                    }
                case .ambiguous:
                    break
                }
            }

            if routeIdentityChanged {
                // The controller may remain usable across metadata enrichment,
                // but its immutable lease cannot. Recreate access lazily.
                state.adjustableDPI = nil
                state.hiResWheel = nil
            }

            guard hardwareTargetChanged else {
                if let stableInitialToRebind, let currentRoute {
                    stableInitialToRebind.lease = Self.reboundLease(
                        stableInitialToRebind.lease,
                        route: currentRoute,
                        token: state.hiResWheelCancellationSource.token
                    )
                }
                return (
                    .init(
                        hardwareTargetChanged: false,
                        candidateAvailabilityChanged: candidateAvailabilityChanged,
                        hasCandidates: discovery?.identities.isEmpty == false
                    ),
                    nil,
                    nil
                )
            }

            let dpiSource = state.dpiCancellationSource
            let wheelSource = state.hiResWheelCancellationSource
            state.dpiCancellationSource = CancellationSource()
            state.hiResWheelCancellationSource = CancellationSource()
            state.adjustableDPI = nil
            state.hiResWheel = nil
            state.sensorDPI = nil
            state.hiResWheelEnabled = nil
            state.hiResWheelMultiplier = nil
            dpiCoordinator.cancel()
            wheelCoordinator.cancel()
            if let stableInitialToRebind, let currentRoute {
                stableInitialToRebind.lease = Self.reboundLease(
                    stableInitialToRebind.lease,
                    route: currentRoute,
                    token: state.hiResWheelCancellationSource.token
                )
            }
            return (
                .init(
                    hardwareTargetChanged: true,
                    candidateAvailabilityChanged: candidateAvailabilityChanged,
                    hasCandidates: discovery?.identities.isEmpty == false
                ),
                dpiSource,
                wheelSource
            )
        }

        update.1?.cancel()
        update.2?.cancel()
        return update.0
    }

    func startDPIApply(
        _ operation: @escaping (HardwareSettingApplyCoordinator.Attempt, CancellationToken) -> Bool
    ) {
        let coordinator = dpiApplyCoordinator
        resetFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource
        ) { token in
            coordinator.start { attempt in
                operation(attempt, token)
            } completion: { [weak self] succeeded in
                guard !succeeded else {
                    return
                }
                self?.clearSensorDPI(for: token)
            }
        }
    }

    func cancelDPIApply() {
        let coordinator = dpiApplyCoordinator
        resetFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource
        ) { _ in coordinator.cancel() }
    }

    func runDPIOperation(
        _ operation: @escaping (CancellationToken) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        runFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            coordinator: dpiApplyCoordinator,
            waitUntilFinished: false,
            operation: operation,
            onCancelled: onCancelled
        )
    }

    func startHiResWheelApply(
        _ operation: @escaping (HardwareSettingApplyCoordinator.Attempt, CancellationToken) -> Bool
    ) {
        let coordinator = hiResWheelApplyCoordinator
        resetFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource,
            mutateState: { $0.hiResWheelRestoreRetryNeeded = false }
        ) { token in
            coordinator.start { attempt in
                operation(attempt, token)
            } completion: { [weak self] succeeded in
                guard !succeeded else {
                    return
                }
                self?.clearHiResWheelState(for: token)
            }
        }
    }

    /// Retries a best-effort return to the pre-managed hardware mode. Unlike
    /// configured-state reconciliation, exhausting this budget must preserve
    /// the last known runtime cache and initial state for a later attempt.
    @discardableResult
    func startHiResWheelRestore(
        _ operation: @escaping (HardwareSettingApplyCoordinator.Attempt, CancellationToken) -> Bool
    ) -> CancellationToken {
        let coordinator = hiResWheelApplyCoordinator
        return resetFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource,
            mutateState: { $0.hiResWheelRestoreRetryNeeded = false }
        ) { token in
            coordinator.start { attempt in
                operation(attempt, token)
            } completion: { [weak self] succeeded in
                self?.finishHiResWheelRestore(succeeded: succeeded, for: token)
            }
        }
    }

    func cancelHiResWheelApply() {
        let coordinator = hiResWheelApplyCoordinator
        resetFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource
        ) { _ in coordinator.cancel() }
    }

    @discardableResult
    func runHiResWheelOperation(
        waitUntilFinished: Bool,
        _ operation: @escaping (CancellationToken) -> Void
    ) -> CancellationToken {
        runFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource,
            coordinator: hiResWheelApplyCoordinator,
            waitUntilFinished: waitUntilFinished,
            operation: operation
        ) {}
    }

    func updateSensorDPI(_ dpi: Int, for access: FeatureAccess<AdjustableDPI>) {
        withState { state in
            guard Self.accessIsCurrent(
                access,
                token: state.dpiCancellationSource.token,
                route: state.discovery?.route
            ) else {
                return
            }
            state.sensorDPI = dpi
        }
    }

    func clearSensorDPI() {
        withState { $0.sensorDPI = nil }
    }

    func clearSensorDPI(for token: CancellationToken) {
        withState { state in
            guard state.dpiCancellationSource.token == token else {
                return
            }
            state.sensorDPI = nil
        }
    }

    func updateHiResWheelState(
        enabled: Bool?,
        multiplier: Int?,
        for access: FeatureAccess<HiResWheel>
    ) {
        withState { state in
            guard Self.accessIsCurrent(access, in: state) else {
                return
            }
            state.hiResWheelEnabled = enabled
            state.hiResWheelMultiplier = enabled == true ? multiplier : nil
        }
    }

    @discardableResult
    func recordInitialHiResWheelState(
        enabled: Bool,
        for access: FeatureAccess<HiResWheel>
    ) -> Bool {
        withState { state in
            guard Self.accessIsCurrent(access, in: state),
                  state.initialHiResWheelState == nil else {
                return false
            }
            state.initialHiResWheelState = .init(
                lease: access.lease,
                enabled: enabled,
                baselineHandle: nil
            )
            return true
        }
    }

    /// Seeds a rebuilt session from a process-lifetime hardware baseline. The
    /// lease must still be current so a receiver replacement can never inherit
    /// another target's original mode.
    @discardableResult
    func seedInitialHiResWheelState(
        _ claim: LogitechHardwareBaselineStore.HiResClaim,
        for lease: TargetLease
    ) -> Bool {
        withState { state in
            guard state.initialHiResWheelState == nil,
                  Self.leaseIsCurrent(lease, in: state),
                  lease.stableTargetKey.map({ claim.handle.belongs(to: $0) }) == true
            else {
                return false
            }
            state.initialHiResWheelState = .init(
                lease: lease,
                enabled: claim.baseline.enabled,
                baselineHandle: claim.handle
            )
            return true
        }
    }

    func initialHiResWheelEnabled(for access: FeatureAccess<HiResWheel>) -> Bool? {
        withState { state in
            guard let initialState = state.initialHiResWheelState,
                  Self.accessIsCurrent(access, in: state),
                  Self.initialState(initialState, matches: access.lease),
                  Self.initialStateRelation(initialState, to: state.discovery?.route) == .compatible
            else {
                return nil
            }
            return initialState.enabled
        }
    }

    /// Captures route, stable key, slot, and cancellation ownership under the
    /// session lock. The key provider must derive identity only from its inputs.
    func hiResWheelTargetLease(
        receiverSlot: UInt8?,
        stableTargetKey: (LogitechReceiverRoute?, UInt8?) -> LogitechHardwareTargetKey?
    ) -> TargetLease? {
        withState { state in
            let token = state.hiResWheelCancellationSource.token
            guard token.shouldContinue else {
                return nil
            }
            let route = state.discovery?.route
            guard route.map({ receiverSlot == nil || $0.slot == receiverSlot }) ?? true else {
                return nil
            }
            let resolvedSlot = receiverSlot ?? route?.slot
            return .init(
                route: route,
                stableTargetKey: stableTargetKey(route, resolvedSlot),
                receiverSlot: resolvedSlot,
                token: token
            )
        }
    }

    func hiResBaselinePromotion(for lease: TargetLease) -> HiResBaselinePromotion? {
        withState { state in
            guard let initialState = state.initialHiResWheelState,
                  initialState.baselineHandle == nil,
                  let stableTargetKey = lease.stableTargetKey,
                  Self.leaseIsCurrent(lease, in: state),
                  Self.initialStateRelation(initialState, to: lease.route) == .compatible,
                  initialState.lease.stableTargetKey.map({ $0 == stableTargetKey }) ?? true
            else {
                return nil
            }
            return .init(
                enabled: initialState.enabled,
                target: stableTargetKey,
                initialState: initialState,
                currentLease: lease
            )
        }
    }

    @discardableResult
    func attachHiResBaseline(
        _ claim: LogitechHardwareBaselineStore.HiResClaim,
        to promotion: HiResBaselinePromotion
    ) -> Bool {
        withState { state in
            guard state.initialHiResWheelState === promotion.initialState,
                  promotion.initialState.baselineHandle == nil,
                  claim.handle.belongs(to: promotion.target),
                  Self.leaseIsCurrent(promotion.currentLease, in: state),
                  Self.initialStateRelation(
                      promotion.initialState,
                      to: state.discovery?.route
                  ) == .compatible
            else {
                return false
            }
            promotion.initialState.lease = promotion.currentLease
            promotion.initialState.enabled = claim.baseline.enabled
            promotion.initialState.baselineHandle = claim.handle
            return true
        }
    }

    var hasInitialHiResWheelState: Bool {
        withState { $0.initialHiResWheelState != nil }
    }

    var hasStoredHiResWheelBaseline: Bool {
        withState { $0.initialHiResWheelState?.baselineHandle != nil }
    }

    var needsHiResWheelRestoreRetry: Bool {
        withState { $0.initialHiResWheelState != nil && $0.hiResWheelRestoreRetryNeeded }
    }

    func clearHiResWheelState(includingInitialState: Bool) {
        withState {
            $0.hiResWheelEnabled = nil
            $0.hiResWheelMultiplier = nil
            if includingInitialState {
                $0.initialHiResWheelState = nil
                $0.hiResWheelRestoreRetryNeeded = false
            }
        }
    }

    /// An exhausted retry budget makes the cached state unknown. The initial
    /// state remains available for a later lifecycle restore.
    func clearHiResWheelState(for token: CancellationToken) {
        withState { state in
            guard state.hiResWheelCancellationSource.token == token else {
                return
            }
            state.hiResWheelEnabled = nil
            state.hiResWheelMultiplier = nil
        }
    }

    /// Commits the hardware mode observed after a successful restore and only
    /// then consumes the initial mode that made that restore possible.
    @discardableResult
    func completeHiResWheelRestore(
        enabled: Bool,
        multiplier: Int?,
        for access: FeatureAccess<HiResWheel>
    ) -> HiResWheelCommit {
        withState { state -> HiResWheelCommit in
            guard let initialState = state.initialHiResWheelState,
                  Self.accessIsCurrent(access, in: state),
                  Self.initialState(initialState, matches: access.lease),
                  Self.initialStateRelation(initialState, to: state.discovery?.route) == .compatible
            else {
                return .rejected
            }
            let baselineHandle = initialState.baselineHandle
            state.hiResWheelEnabled = enabled
            state.hiResWheelMultiplier = enabled ? multiplier : nil
            state.initialHiResWheelState = nil
            state.hiResWheelRestoreRetryNeeded = false
            return .committed(baselineHandle)
        }
    }

    /// Used by lifecycle teardown, which intentionally clears runtime cache
    /// rather than retaining the restored mode for normalization.
    @discardableResult
    func consumeHiResWheelState(for access: FeatureAccess<HiResWheel>) -> HiResWheelCommit {
        withState { state -> HiResWheelCommit in
            guard let initialState = state.initialHiResWheelState,
                  Self.accessIsCurrent(access, in: state),
                  Self.initialState(initialState, matches: access.lease),
                  Self.initialStateRelation(initialState, to: state.discovery?.route) == .compatible
            else {
                return .rejected
            }
            let baselineHandle = initialState.baselineHandle
            state.hiResWheel = nil
            state.hiResWheelEnabled = nil
            state.hiResWheelMultiplier = nil
            state.initialHiResWheelState = nil
            state.hiResWheelRestoreRetryNeeded = false
            return .committed(baselineHandle)
        }
    }

    private func finishHiResWheelRestore(succeeded: Bool, for token: CancellationToken) {
        withState { state in
            guard state.hiResWheelCancellationSource.token == token else {
                return
            }
            state.hiResWheelRestoreRetryNeeded = !succeeded && state.initialHiResWheelState != nil
        }
    }

    @discardableResult
    private func resetFeatureOperation<Feature>(
        cache: WritableKeyPath<State, FeatureAccess<Feature>?>,
        cancellationSource: WritableKeyPath<State, CancellationSource>,
        mutateState: (inout State) -> Void = { _ in },
        updateCoordinator: (CancellationToken) -> Void
    ) -> CancellationToken {
        let source = CancellationSource()
        let previousSource = withState { state -> CancellationSource in
            let previousSource = state[keyPath: cancellationSource]
            state[keyPath: cancellationSource] = source
            state[keyPath: cache] = nil
            mutateState(&state)
            updateCoordinator(source.token)
            return previousSource
        }
        previousSource.cancel()
        return source.token
    }

    @discardableResult
    private func runFeatureOperation<Feature>(
        cache: WritableKeyPath<State, FeatureAccess<Feature>?>,
        cancellationSource: WritableKeyPath<State, CancellationSource>,
        coordinator: HardwareSettingApplyCoordinator,
        waitUntilFinished: Bool,
        operation: @escaping (CancellationToken) -> Void,
        onCancelled: @escaping () -> Void
    ) -> CancellationToken {
        let token = resetFeatureOperation(
            cache: cache,
            cancellationSource: cancellationSource
        ) { _ in coordinator.cancel() }
        let guardedOperation = {
            guard token.shouldContinue else {
                onCancelled()
                return
            }
            operation(token)
        }
        if waitUntilFinished {
            if Thread.isMainThread {
                // Direct HID report callbacks are delivered by the main run
                // loop. Drain cancelled queued work without blocking it, then
                // issue the teardown request on that run loop.
                drainQueueOnCurrentRunLoop()
                guardedOperation()
            } else {
                performSynchronously(guardedOperation)
            }
        } else {
            perform(guardedOperation)
        }
        return token
    }

    private func drainQueueOnCurrentRunLoop() {
        let drained = DispatchSemaphore(value: 0)
        queue.async {
            drained.signal()
        }
        while drained.wait(timeout: .now()) == .timedOut {
            _ = CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
    }

    func invalidateHiResWheel(for token: CancellationToken) {
        withState { state in
            guard state.hiResWheelCancellationSource.token == token else {
                return
            }
            state.hiResWheel = nil
        }
    }

    func adjustableDPI(
        expectedToken: CancellationToken? = nil,
        create: (LogitechReceiverRoute?, CancellationToken) -> FeatureBinding<AdjustableDPI>?
    ) -> FeatureAccess<AdjustableDPI>? {
        feature(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            expectedToken: expectedToken,
            create: create
        )
    }

    func hiResWheel(
        expectedToken: CancellationToken? = nil,
        create: (LogitechReceiverRoute?, CancellationToken) -> FeatureBinding<HiResWheel>?
    ) -> FeatureAccess<HiResWheel>? {
        let admitted = withState { state in
            guard let initialState = state.initialHiResWheelState else {
                return true
            }
            return Self.initialStateRelation(initialState, to: state.discovery?.route) == .compatible
        }
        guard admitted else {
            return nil
        }
        return feature(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource,
            expectedToken: expectedToken,
            create: create
        )
    }

    func cancelAll() {
        let dpiCoordinator = dpiApplyCoordinator
        let wheelCoordinator = hiResWheelApplyCoordinator
        let sources = withState { state -> (CancellationSource, CancellationSource) in
            let sources = (state.dpiCancellationSource, state.hiResWheelCancellationSource)
            state = State()
            dpiCoordinator.cancel()
            wheelCoordinator.cancel()
            return sources
        }
        sources.0.cancel()
        sources.1.cancel()
    }

    private func feature<Feature>(
        cache: WritableKeyPath<State, FeatureAccess<Feature>?>,
        cancellationSource: KeyPath<State, CancellationSource>,
        expectedToken: CancellationToken?,
        create: (LogitechReceiverRoute?, CancellationToken) -> FeatureBinding<Feature>?
    ) -> FeatureAccess<Feature>? {
        let snapshot = withState { state in
            (
                cached: state[keyPath: cache],
                route: state.discovery?.route,
                token: state[keyPath: cancellationSource].token
            )
        }
        guard snapshot.token.shouldContinue else {
            return nil
        }
        if let expectedToken, expectedToken != snapshot.token {
            return nil
        }
        if let cached = snapshot.cached {
            return cached
        }

        guard let binding = create(snapshot.route, snapshot.token)
        else {
            return nil
        }

        return withState { state in
            let currentToken = state[keyPath: cancellationSource].token
            guard currentToken == snapshot.token,
                  currentToken.shouldContinue,
                  snapshot.route == state.discovery?.route
            else {
                return nil
            }

            let access = FeatureAccess(
                feature: binding.feature,
                lease: .init(
                    route: snapshot.route,
                    stableTargetKey: binding.stableTargetKey,
                    receiverSlot: binding.receiverSlot,
                    token: currentToken
                )
            )
            state[keyPath: cache] = access
            return access
        }
    }

    private static func accessIsCurrent<Feature>(
        _ access: FeatureAccess<Feature>,
        token: CancellationToken,
        route: LogitechReceiverRoute?
    ) -> Bool {
        access.token == token
            && access.token.shouldContinue
            && routeCanContinue(from: access.lease.route, to: route)
    }

    private static func accessIsCurrent(
        _ access: FeatureAccess<HiResWheel>,
        in state: State
    ) -> Bool {
        accessIsCurrent(
            access,
            token: state.hiResWheelCancellationSource.token,
            route: state.discovery?.route
        )
    }

    private static func leaseIsCurrent(_ lease: TargetLease, in state: State) -> Bool {
        lease.token == state.hiResWheelCancellationSource.token
            && lease.token.shouldContinue
            && routeCanContinue(from: lease.route, to: state.discovery?.route)
    }

    /// Directional compatibility for an operation that started at `previous`.
    /// Metadata may be enriched, but known identity cannot be downgraded.
    private static func routeCanContinue(
        from previous: LogitechReceiverRoute?,
        to current: LogitechReceiverRoute?
    ) -> Bool {
        guard let previous, let current else {
            return previous == nil && current == nil
        }
        guard previous.slot == current.slot,
              previous.identity.receiverLocationID == current.identity.receiverLocationID else {
            return false
        }

        let previousSerial = normalizedSerial(previous.identity.serialNumber)
        let currentSerial = normalizedSerial(current.identity.serialNumber)
        if let previousSerial {
            return currentSerial == previousSerial
        }
        if let previousProductID = previous.identity.productID,
           let currentProductID = current.identity.productID,
           previousProductID != currentProductID {
            return false
        }
        return true
    }

    private enum InitialStateRelation {
        case compatible
        case ambiguous
        case different
    }

    private static func initialState(
        _ initialState: InitialHiResWheelState,
        matches lease: TargetLease
    ) -> Bool {
        guard initialState.lease.receiverSlot == lease.receiverSlot else {
            return false
        }
        return initialState.lease.stableTargetKey.map { $0 == lease.stableTargetKey } ?? true
    }

    private static func initialStateRelation(
        _ initialState: InitialHiResWheelState,
        to currentRoute: LogitechReceiverRoute?
    ) -> InitialStateRelation {
        guard let initialRoute = initialState.lease.route else {
            return currentRoute == nil ? .compatible : .different
        }
        guard let currentRoute else {
            return .ambiguous
        }
        if let initialSerial = normalizedSerial(initialRoute.identity.serialNumber) {
            guard let currentSerial = normalizedSerial(currentRoute.identity.serialNumber) else {
                return .ambiguous
            }
            return currentSerial == initialSerial ? .compatible : .different
        }
        guard initialRoute.slot == currentRoute.slot,
              initialRoute.identity.receiverLocationID == currentRoute.identity.receiverLocationID,
              initialState.lease.receiverSlot == currentRoute.slot else {
            return .different
        }
        if let initialProductID = initialRoute.identity.productID,
           let currentProductID = currentRoute.identity.productID,
           initialProductID != currentProductID {
            return .different
        }
        return .compatible
    }

    private static func reboundLease(
        _ lease: TargetLease,
        route: LogitechReceiverRoute,
        token: CancellationToken
    ) -> TargetLease {
        .init(
            route: route,
            stableTargetKey: lease.stableTargetKey,
            receiverSlot: route.slot,
            token: token
        )
    }

    private static func normalizedSerial(_ serial: String?) -> String? {
        guard let serial else {
            return nil
        }
        let normalized = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func makeApplyCoordinator(queue: DispatchQueue) -> HardwareSettingApplyCoordinator {
        HardwareSettingApplyCoordinator { delay, work in
            let workItem = DispatchWorkItem(block: work)
            if delay <= 0 {
                queue.async(execute: workItem)
            } else {
                queue.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }
}
