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

    fileprivate final class InitialTargetState<Value, Handle> {
        var lease: TargetLease
        var value: Value
        var baselineHandle: Handle?

        init(
            lease: TargetLease,
            value: Value,
            baselineHandle: Handle?
        ) {
            self.lease = lease
            self.value = value
            self.baselineHandle = baselineHandle
        }
    }

    fileprivate typealias InitialDPIState = InitialTargetState<
        Int,
        LogitechHardwareBaselineStore.DPIHandle
    >
    fileprivate typealias InitialHiResWheelState = InitialTargetState<
        Bool,
        LogitechHardwareBaselineStore.HiResHandle
    >

    struct DPIBaselinePromotion {
        let dpi: Int
        let target: LogitechHardwareTargetKey
        fileprivate let initialState: InitialDPIState
        fileprivate let currentLease: TargetLease
    }

    enum DPICommit {
        case committed(LogitechHardwareBaselineStore.DPIHandle?)
        case rejected
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
        var initialDPIState: InitialDPIState?
        var dpiRestoreRetryNeeded = false
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

            let dpiTransition = Self.transitionInitialState(
                state.initialDPIState,
                from: previousRoute,
                to: currentRoute
            )
            let wheelTransition = Self.transitionInitialState(
                state.initialHiResWheelState,
                from: previousRoute,
                to: currentRoute
            )
            state.initialDPIState = dpiTransition.state
            state.initialHiResWheelState = wheelTransition.state
            hardwareTargetChanged = hardwareTargetChanged
                || dpiTransition.requiresTargetReset
                || wheelTransition.requiresTargetReset
            state.discovery = discovery

            if routeIdentityChanged {
                // The controller may remain usable across metadata enrichment,
                // but its immutable lease cannot. Recreate access lazily.
                state.adjustableDPI = nil
                state.hiResWheel = nil
            }

            guard hardwareTargetChanged else {
                if let currentRoute {
                    Self.rebindStableInitialState(
                        state.initialDPIState,
                        to: currentRoute,
                        token: state.dpiCancellationSource.token
                    )
                    Self.rebindStableInitialState(
                        state.initialHiResWheelState,
                        to: currentRoute,
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
            if let currentRoute {
                Self.rebindStableInitialState(
                    state.initialDPIState,
                    to: currentRoute,
                    token: state.dpiCancellationSource.token
                )
                Self.rebindStableInitialState(
                    state.initialHiResWheelState,
                    to: currentRoute,
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
            cancellationSource: \State.dpiCancellationSource,
            mutateState: { $0.dpiRestoreRetryNeeded = false }
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

    /// Retries a return to the pre-managed DPI without discarding its
    /// baseline when the device is temporarily unavailable.
    @discardableResult
    func startDPIRestore(
        _ operation: @escaping (HardwareSettingApplyCoordinator.Attempt, CancellationToken) -> Bool
    ) -> CancellationToken {
        let coordinator = dpiApplyCoordinator
        return resetFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            mutateState: { $0.dpiRestoreRetryNeeded = false }
        ) { token in
            coordinator.start { attempt in
                operation(attempt, token)
            } completion: { [weak self] succeeded in
                self?.finishDPIRestore(succeeded: succeeded, for: token)
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

    @discardableResult
    func runDPIOperation(
        waitUntilFinished: Bool = false,
        _ operation: @escaping (CancellationToken) -> Void,
        onCancelled: @escaping () -> Void
    ) -> CancellationToken {
        runFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            coordinator: dpiApplyCoordinator,
            waitUntilFinished: waitUntilFinished,
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

    @discardableResult
    func recordInitialSensorDPI(
        _ dpi: Int,
        for access: FeatureAccess<AdjustableDPI>
    ) -> Bool {
        withState { state in
            guard Self.accessIsCurrent(
                access,
                token: state.dpiCancellationSource.token,
                route: state.discovery?.route
            ), state.initialDPIState == nil else {
                return false
            }
            state.initialDPIState = .init(
                lease: access.lease,
                value: dpi,
                baselineHandle: nil
            )
            return true
        }
    }

    /// Seeds a rebuilt session only from a baseline whose stable target still
    /// belongs to the current immutable DPI lease.
    @discardableResult
    func seedInitialSensorDPI(
        _ claim: LogitechHardwareBaselineStore.DPIClaim,
        for lease: TargetLease
    ) -> Bool {
        withState { state in
            guard state.initialDPIState == nil,
                  Self.leaseIsCurrent(
                      lease,
                      token: state.dpiCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  lease.stableTargetKey.map({ claim.handle.belongs(to: $0) }) == true
            else {
                return false
            }
            state.initialDPIState = .init(
                lease: lease,
                value: claim.baseline.value,
                baselineHandle: claim.handle
            )
            return true
        }
    }

    func initialSensorDPI(for access: FeatureAccess<AdjustableDPI>) -> Int? {
        withState { state in
            guard let initialState = state.initialDPIState,
                  Self.accessIsCurrent(
                      access,
                      token: state.dpiCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  Self.initialState(initialState, matches: access.lease),
                  Self.initialStateRelation(initialState, to: state.discovery?.route) == .compatible
            else {
                return nil
            }
            return initialState.value
        }
    }

    func dpiTargetLease(
        receiverSlot: UInt8?,
        stableTargetKey: (LogitechReceiverRoute?, UInt8?) -> LogitechHardwareTargetKey?
    ) -> TargetLease? {
        withState { state in
            Self.targetLease(
                receiverSlot: receiverSlot,
                cachedReceiverSlot: state.adjustableDPI?.lease.receiverSlot,
                initialReceiverSlot: state.initialDPIState?.lease.receiverSlot,
                route: state.discovery?.route,
                token: state.dpiCancellationSource.token,
                stableTargetKey: stableTargetKey
            )
        }
    }

    func dpiBaselinePromotion(for lease: TargetLease) -> DPIBaselinePromotion? {
        withState { state in
            guard let initialState = state.initialDPIState,
                  initialState.baselineHandle == nil,
                  let stableTargetKey = lease.stableTargetKey,
                  Self.leaseIsCurrent(
                      lease,
                      token: state.dpiCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  Self.initialStateRelation(initialState, to: lease.route) == .compatible,
                  Self.initialState(initialState, matches: lease)
            else {
                return nil
            }
            return .init(
                dpi: initialState.value,
                target: stableTargetKey,
                initialState: initialState,
                currentLease: lease
            )
        }
    }

    @discardableResult
    func attachDPIBaseline(
        _ claim: LogitechHardwareBaselineStore.DPIClaim,
        to promotion: DPIBaselinePromotion
    ) -> Bool {
        withState { state in
            guard state.initialDPIState === promotion.initialState,
                  promotion.initialState.baselineHandle == nil,
                  claim.handle.belongs(to: promotion.target),
                  Self.leaseIsCurrent(
                      promotion.currentLease,
                      token: state.dpiCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  Self.initialStateRelation(
                      promotion.initialState,
                      to: state.discovery?.route
                  ) == .compatible
            else {
                return false
            }
            promotion.initialState.lease = promotion.currentLease
            promotion.initialState.value = claim.baseline.value
            promotion.initialState.baselineHandle = claim.handle
            return true
        }
    }

    var hasInitialSensorDPIState: Bool {
        withState { $0.initialDPIState != nil }
    }

    var hasStoredSensorDPIBaseline: Bool {
        withState { $0.initialDPIState?.baselineHandle != nil }
    }

    var needsDPIRestoreRetry: Bool {
        withState { $0.initialDPIState != nil && $0.dpiRestoreRetryNeeded }
    }

    /// Commits a read-back-confirmed restore. The caller may then consume only
    /// the exact process-store handle returned here.
    @discardableResult
    func completeSensorDPIRestore(
        dpi: Int,
        for access: FeatureAccess<AdjustableDPI>
    ) -> DPICommit {
        withState { state -> DPICommit in
            guard let initialState = state.initialDPIState,
                  Self.accessIsCurrent(
                      access,
                      token: state.dpiCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  Self.initialState(initialState, matches: access.lease),
                  Self.initialStateRelation(initialState, to: state.discovery?.route) == .compatible,
                  initialState.value == dpi
            else {
                return .rejected
            }
            let baselineHandle = initialState.baselineHandle
            state.sensorDPI = dpi
            state.initialDPIState = nil
            state.dpiRestoreRetryNeeded = false
            return .committed(baselineHandle)
        }
    }

    func invalidateAdjustableDPI(for token: CancellationToken) {
        withState { state in
            guard state.dpiCancellationSource.token == token else {
                return
            }
            state.adjustableDPI = nil
        }
    }

    private func finishDPIRestore(succeeded: Bool, for token: CancellationToken) {
        withState { state in
            guard state.dpiCancellationSource.token == token else {
                return
            }
            state.dpiRestoreRetryNeeded = !succeeded && state.initialDPIState != nil
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
                value: enabled,
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
                  Self.leaseIsCurrent(
                      lease,
                      token: state.hiResWheelCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  lease.stableTargetKey.map({ claim.handle.belongs(to: $0) }) == true
            else {
                return false
            }
            state.initialHiResWheelState = .init(
                lease: lease,
                value: claim.baseline.enabled,
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
            return initialState.value
        }
    }

    /// Captures route, stable key, slot, and cancellation ownership under the
    /// session lock. The key provider must derive identity only from its inputs.
    func hiResWheelTargetLease(
        receiverSlot: UInt8?,
        stableTargetKey: (LogitechReceiverRoute?, UInt8?) -> LogitechHardwareTargetKey?
    ) -> TargetLease? {
        withState { state in
            Self.targetLease(
                receiverSlot: receiverSlot,
                cachedReceiverSlot: state.hiResWheel?.lease.receiverSlot,
                initialReceiverSlot: state.initialHiResWheelState?.lease.receiverSlot,
                route: state.discovery?.route,
                token: state.hiResWheelCancellationSource.token,
                stableTargetKey: stableTargetKey
            )
        }
    }

    func hiResBaselinePromotion(for lease: TargetLease) -> HiResBaselinePromotion? {
        withState { state in
            guard let initialState = state.initialHiResWheelState,
                  initialState.baselineHandle == nil,
                  let stableTargetKey = lease.stableTargetKey,
                  Self.leaseIsCurrent(
                      lease,
                      token: state.hiResWheelCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  Self.initialStateRelation(initialState, to: lease.route) == .compatible,
                  Self.initialState(initialState, matches: lease)
            else {
                return nil
            }
            return .init(
                enabled: initialState.value,
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
                  Self.leaseIsCurrent(
                      promotion.currentLease,
                      token: state.hiResWheelCancellationSource.token,
                      route: state.discovery?.route
                  ),
                  Self.initialStateRelation(
                      promotion.initialState,
                      to: state.discovery?.route
                  ) == .compatible
            else {
                return false
            }
            promotion.initialState.lease = promotion.currentLease
            promotion.initialState.value = claim.baseline.enabled
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
        let admitted = withState { state in
            guard let initialState = state.initialDPIState else {
                return true
            }
            return Self.initialStateRelation(initialState, to: state.discovery?.route) == .compatible
        }
        guard admitted else {
            return nil
        }
        return feature(
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

    private static func leaseIsCurrent(
        _ lease: TargetLease,
        token: CancellationToken,
        route: LogitechReceiverRoute?
    ) -> Bool {
        lease.token == token
            && lease.token.shouldContinue
            && routeCanContinue(from: lease.route, to: route)
    }

    /// Builds a lease from one state snapshot. A legacy on-demand receiver's
    /// resolved slot must survive cache invalidation so it is never mistaken
    /// for the directly-addressable receiver itself.
    private static func targetLease(
        receiverSlot: UInt8?,
        cachedReceiverSlot: UInt8?,
        initialReceiverSlot: UInt8?,
        route: LogitechReceiverRoute?,
        token: CancellationToken,
        stableTargetKey: (LogitechReceiverRoute?, UInt8?) -> LogitechHardwareTargetKey?
    ) -> TargetLease? {
        guard token.shouldContinue else {
            return nil
        }
        let resolvedSlot = receiverSlot
            ?? cachedReceiverSlot
            ?? initialReceiverSlot
            ?? route?.slot
        guard route.map({ resolvedSlot == nil || $0.slot == resolvedSlot }) ?? true else {
            return nil
        }
        return .init(
            route: route,
            stableTargetKey: stableTargetKey(route, resolvedSlot),
            receiverSlot: resolvedSlot,
            token: token
        )
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

    private static func transitionInitialState<Value, Handle>(
        _ initialState: InitialTargetState<Value, Handle>?,
        from previousRoute: LogitechReceiverRoute?,
        to currentRoute: LogitechReceiverRoute?
    ) -> (state: InitialTargetState<Value, Handle>?, requiresTargetReset: Bool) {
        guard let initialState else {
            return (nil, false)
        }

        let wasUsable = initialStateRelation(initialState, to: previousRoute) == .compatible

        // A receiver baseline without a stable identity cannot safely cross
        // route loss because its old slot may later address another device.
        if currentRoute == nil,
           initialState.lease.route != nil,
           initialState.lease.stableTargetKey == nil {
            return (nil, false)
        }

        guard let currentRoute else {
            return (initialState, false)
        }

        switch initialStateRelation(initialState, to: currentRoute) {
        case .different:
            return (nil, true)
        case .compatible:
            return (initialState, !wasUsable)
        case .ambiguous:
            return (initialState, false)
        }
    }

    private static func rebindStableInitialState<Value, Handle>(
        _ initialState: InitialTargetState<Value, Handle>?,
        to route: LogitechReceiverRoute,
        token: CancellationToken
    ) {
        guard let initialState,
              initialState.lease.stableTargetKey != nil,
              initialStateRelation(initialState, to: route) == .compatible else {
            return
        }
        initialState.lease = reboundLease(initialState.lease, route: route, token: token)
    }

    private static func initialState<Value, Handle>(
        _ initialState: InitialTargetState<Value, Handle>,
        matches lease: TargetLease
    ) -> Bool {
        guard initialState.lease.receiverSlot == lease.receiverSlot else {
            return false
        }
        return initialState.lease.stableTargetKey.map { $0 == lease.stableTargetKey } ?? true
    }

    private static func initialStateRelation<Value, Handle>(
        _ initialState: InitialTargetState<Value, Handle>,
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
