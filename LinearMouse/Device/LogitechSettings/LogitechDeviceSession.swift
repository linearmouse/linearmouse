// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP

/// Concrete ownership of one suspended hardware-settings lifetime.
///
/// Object identity prevents a delayed wake from reopening ordinary HID++
/// access after a terminal restore has superseded that exact suspension.
final class LogitechHardwareSuspension {
    fileprivate init() {}
}

enum LogitechTerminalHardwareRestoreRetry {
    /// Concrete ownership for one bounded hardware attempt. Cancelling or
    /// leaving its fair time slice makes every subsequent HID request and
    /// pre-write check fail without relying on a shared counter.
    final class Attempt {
        let deadline: Date

        private let cancellationSource = CancellationSource()
        private let parentShouldContinue: () -> Bool
        private let now: () -> Date

        fileprivate init(
            deadline: Date,
            parentShouldContinue: @escaping () -> Bool,
            now: @escaping () -> Date
        ) {
            self.deadline = deadline
            self.parentShouldContinue = parentShouldContinue
            self.now = now
        }

        func shouldContinue() -> Bool {
            cancellationSource.token.shouldContinue
                && parentShouldContinue()
                && now() < deadline
        }

        fileprivate func cancel() {
            cancellationSource.cancel()
        }
    }

    struct Operation {
        let shouldContinue: () -> Bool
        let attempt: (Attempt) -> Bool
    }

    /// Retries only unfinished settings while their concrete owners and the
    /// shared teardown deadline remain valid. Independent results prevent one
    /// unavailable feature from starving restoration of another.
    static func perform(
        operations: [Operation],
        deadline: Date,
        now: @escaping () -> Date = Date.init,
        wait: (TimeInterval) -> Void
    ) -> Bool {
        guard !operations.isEmpty else {
            return true
        }

        var completed = [Bool](repeating: false, count: operations.count)
        var backoff = ExponentialBackoff(initialDelay: 0.05, maximumDelay: 0.5)

        while now() < deadline {
            let runnable = operations.indices.filter {
                !completed[$0]
                    && operations[$0].shouldContinue()
            }
            var attempted = false
            for (position, index) in runnable.enumerated() {
                let operation = operations[index]
                guard operation.shouldContinue(), now() < deadline else {
                    continue
                }
                let remainingOperationCount = runnable.count - position
                let attemptStart = now()
                let remaining = deadline.timeIntervalSince(attemptStart)
                guard remaining > 0 else {
                    break
                }
                let attempt = Attempt(
                    deadline: min(
                        deadline,
                        attemptStart.addingTimeInterval(
                            remaining / Double(remainingOperationCount)
                        )
                    ),
                    parentShouldContinue: operation.shouldContinue,
                    now: now
                )
                attempted = true
                completed[index] = operation.attempt(attempt)
                attempt.cancel()
            }

            if completed.allSatisfy(\.self) {
                return true
            }
            let hasRunnableOperation = operations.indices.contains {
                !completed[$0]
                    && operations[$0].shouldContinue()
            }
            guard attempted, hasRunnableOperation else {
                break
            }

            let remaining = deadline.timeIntervalSince(now())
            guard remaining > 0 else {
                break
            }
            wait(min(backoff.nextDelay(), remaining))
        }

        return completed.allSatisfy(\.self)
    }
}

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

    /// Concrete ownership for the final hardware restore. Once installed, the
    /// Device is leaving this observation lifetime and no new setting mutation
    /// may supersede the restore.
    private final class TerminalHardwareRestoreRequest {}

    private enum LifecycleOwner {
        case suspension(LogitechHardwareSuspension)
        case terminal(TerminalHardwareRestoreRequest)

        func owns(_ suspension: LogitechHardwareSuspension) -> Bool {
            guard case let .suspension(owner) = self else {
                return false
            }
            return owner === suspension
        }

        func owns(_ request: TerminalHardwareRestoreRequest) -> Bool {
            guard case let .terminal(owner) = self else {
                return false
            }
            return owner === request
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
        var provisionalHiResWheelMultiplier: Int?
        var initialHiResWheelState: InitialHiResWheelState?
        var hiResWheelRestoreRetryNeeded = false
        var ordinaryHardwareAccess = CancellationSource()
        var lifecycleOwner: LifecycleOwner?
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
            guard state.lifecycleOwner == nil else {
                return nil
            }
            if state.hiResWheelEnabled == true,
               let multiplier = state.hiResWheelMultiplier,
               multiplier > 0 {
                return multiplier
            }

            guard state.hiResWheelEnabled != false,
                  let multiplier = state.provisionalHiResWheelMultiplier,
                  multiplier > 0 else {
                return nil
            }
            return multiplier
        }
    }

    var allowsOrdinaryHardwareIO: Bool {
        withState { Self.ordinaryHardwareIOIsAdmitted($0) }
    }

    var dpiReceiverSlotSnapshot: UInt8? {
        withState {
            $0.discovery?.route?.slot
                ?? $0.adjustableDPI?.lease.receiverSlot
                ?? $0.initialDPIState?.lease.receiverSlot
        }
    }

    var hiResWheelReceiverSlotSnapshot: UInt8? {
        withState {
            $0.discovery?.route?.slot
                ?? $0.hiResWheel?.lease.receiverSlot
                ?? $0.initialHiResWheelState?.lease.receiverSlot
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

    /// Runs a read-only HID operation under the same admission used by every
    /// configured mutation. Sleep or terminal teardown closes the concrete
    /// ordinary-access owner immediately, so queued and in-flight reads yield
    /// without delaying lifecycle restoration.
    func runBoundedOrdinaryHardwareRead(
        deadline: Date,
        _ operation: @escaping (_ shouldContinue: @escaping () -> Bool) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        let access = withState { state -> CancellationSource? in
            guard Self.ordinaryHardwareIOIsAdmitted(state) else {
                return nil
            }
            return state.ordinaryHardwareAccess
        }
        guard let access else {
            onCancelled()
            return
        }

        perform {
            let shouldContinue = { [weak self] in
                access.token.shouldContinue
                    && Date() < deadline
                    && self?.withState {
                        $0.ordinaryHardwareAccess === access
                            && Self.ordinaryHardwareIOIsAdmitted($0)
                    } == true
            }
            guard shouldContinue() else {
                onCancelled()
                return
            }
            operation(shouldContinue)
        }
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
            state.provisionalHiResWheelMultiplier = nil
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
        } ?? Self.cancelledToken()
    }

    func cancelDPIApply() {
        let coordinator = dpiApplyCoordinator
        _ = resetFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            admittedDuringLifecycle: true
        ) { _ in coordinator.cancel() }
    }

    @discardableResult
    func runDPIOperation(
        _ operation: @escaping (CancellationToken) -> Void,
        onCancelled: @escaping () -> Void
    ) -> CancellationToken {
        runFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            coordinator: dpiApplyCoordinator,
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
        } ?? Self.cancelledToken()
    }

    func cancelHiResWheelApply() {
        let coordinator = hiResWheelApplyCoordinator
        _ = resetFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource,
            admittedDuringLifecycle: true
        ) { _ in coordinator.cancel() }
    }

    /// Atomically revokes ordinary reads and both configured setting pipelines
    /// without restoring hardware or consuming their initial baselines.
    ///
    /// The replacement feature tokens remain available to a stronger terminal
    /// owner. A normal resume merely removes this exact suspension owner, so a
    /// delayed resume can never reopen a session already claimed by teardown.
    func suspendHardware() -> LogitechHardwareSuspension? {
        let dpiCoordinator = dpiApplyCoordinator
        let wheelCoordinator = hiResWheelApplyCoordinator
        let transition = withState { state -> (
            suspension: LogitechHardwareSuspension?,
            previousSources: (CancellationSource, CancellationSource, CancellationSource)?
        ) in
            switch state.lifecycleOwner {
            case let .suspension(existing)?:
                return (existing, nil)
            case .terminal?:
                return (nil, nil)
            case nil:
                let suspension = LogitechHardwareSuspension()
                let previousSources = (
                    state.ordinaryHardwareAccess,
                    state.dpiCancellationSource,
                    state.hiResWheelCancellationSource
                )

                if state.hiResWheelEnabled == true,
                   let multiplier = state.hiResWheelMultiplier,
                   multiplier > 0 {
                    state.provisionalHiResWheelMultiplier = multiplier
                } else if state.hiResWheelEnabled == false {
                    state.provisionalHiResWheelMultiplier = nil
                }

                state.lifecycleOwner = .suspension(suspension)
                state.ordinaryHardwareAccess = CancellationSource()
                state.dpiCancellationSource = CancellationSource()
                state.hiResWheelCancellationSource = CancellationSource()
                state.adjustableDPI = nil
                state.hiResWheel = nil
                state.sensorDPI = nil
                state.hiResWheelEnabled = nil
                state.hiResWheelMultiplier = nil
                dpiCoordinator.cancel()
                wheelCoordinator.cancel()
                return (suspension, previousSources)
            }
        }

        guard let suspension = transition.suspension else {
            return nil
        }
        guard let previousSources = transition.previousSources else {
            return suspension
        }

        previousSources.0.cancel()
        previousSources.1.cancel()
        previousSources.2.cancel()
        return suspension
    }

    /// Reopens ordinary hardware access only for the exact current suspension.
    @discardableResult
    func resumeHardware(from suspension: LogitechHardwareSuspension) -> Bool {
        withState { state in
            guard state.lifecycleOwner?.owns(suspension) == true else {
                return false
            }
            state.lifecycleOwner = nil
            return true
        }
    }

    /// Runs the final DPI and wheel restore on the existing per-device queue.
    ///
    /// Normal apply/confirmation work is cancelled first, but the current
    /// feature transports and target leases are retained. This avoids
    /// rebuilding a feature (and re-reading its capabilities) during the
    /// bounded termination window. A later target transition or timeout still
    /// cancels the captured tokens in the usual way.
    func freezeTerminalHardwareMutations() {
        _ = terminalHardwareRestoreSnapshot()
        dpiApplyCoordinator.cancel()
        hiResWheelApplyCoordinator.cancel()
    }

    func runTerminalHardwareRestore(
        _ operation: @escaping (
            _ dpiToken: CancellationToken,
            _ wheelToken: CancellationToken,
            _ ownsTerminalRestore: @escaping () -> Bool
        ) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        let snapshot = terminalHardwareRestoreSnapshot()
        let request = snapshot.request
        let tokens = snapshot.tokens

        dpiApplyCoordinator.cancel()
        hiResWheelApplyCoordinator.cancel()

        perform {
            let ownsTerminalRestore = { [weak self] in
                self?.withState {
                    $0.lifecycleOwner?.owns(request) == true
                } == true
            }
            guard ownsTerminalRestore() else {
                onCancelled()
                return
            }
            operation(tokens.0, tokens.1, ownsTerminalRestore)
        }
    }

    private func terminalHardwareRestoreSnapshot() -> (
        request: TerminalHardwareRestoreRequest,
        tokens: (CancellationToken, CancellationToken),
        ordinaryAccess: CancellationSource
    ) {
        let snapshot = withState { state in
            let request: TerminalHardwareRestoreRequest
            if case let .terminal(owner) = state.lifecycleOwner {
                request = owner
            } else {
                request = TerminalHardwareRestoreRequest()
                state.lifecycleOwner = .terminal(request)
            }
            return (
                request: request,
                tokens: (state.dpiCancellationSource.token, state.hiResWheelCancellationSource.token),
                ordinaryAccess: state.ordinaryHardwareAccess
            )
        }
        snapshot.ordinaryAccess.cancel()
        return snapshot
    }

    /// Ordinary configured/manual writes lose admission as soon as a concrete
    /// terminal owner is installed. Feature transports check this again at the
    /// actual report send boundary, after any preceding read has completed.
    func allowsConfiguredDPIOperation(for token: CancellationToken) -> Bool {
        withState { state in
            Self.ordinaryHardwareIOIsAdmitted(state)
                && state.dpiCancellationSource.token == token
                && token.shouldContinue
        }
    }

    func allowsConfiguredHiResWheelOperation(for token: CancellationToken) -> Bool {
        withState { state in
            Self.ordinaryHardwareIOIsAdmitted(state)
                && state.hiResWheelCancellationSource.token == token
                && token.shouldContinue
        }
    }

    func allowsConfiguredDPIWrite(for access: FeatureAccess<AdjustableDPI>) -> Bool {
        withState { state in
            Self.ordinaryHardwareIOIsAdmitted(state)
                && Self.accessIsCurrent(
                    access,
                    token: state.dpiCancellationSource.token,
                    route: state.discovery?.route
                )
        }
    }

    func allowsConfiguredHiResWheelWrite(for access: FeatureAccess<HiResWheel>) -> Bool {
        withState { state in
            Self.ordinaryHardwareIOIsAdmitted(state)
                && Self.accessIsCurrent(access, in: state)
        }
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
            if enabled == nil,
               state.provisionalHiResWheelMultiplier != nil,
               let multiplier,
               multiplier > 0 {
                state.provisionalHiResWheelMultiplier = multiplier
            } else if enabled == false || multiplier.map({ $0 > 0 }) == true {
                state.provisionalHiResWheelMultiplier = nil
            }
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

    var needsHiResWheelRestoreRetry: Bool {
        withState { $0.initialHiResWheelState != nil && $0.hiResWheelRestoreRetryNeeded }
    }

    func clearConfirmedHiResWheelState() {
        withState {
            $0.hiResWheelEnabled = nil
            $0.hiResWheelMultiplier = nil
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
            state.provisionalHiResWheelMultiplier = nil
        }
    }

    func clearProvisionalHiResWheelMultiplier(for token: CancellationToken) {
        withState { state in
            guard state.hiResWheelCancellationSource.token == token,
                  state.hiResWheelEnabled == nil else {
                return
            }
            state.provisionalHiResWheelMultiplier = nil
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
            state.provisionalHiResWheelMultiplier = nil
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
        admittedDuringLifecycle: Bool = false,
        updateCoordinator: (CancellationToken) -> Void
    ) -> CancellationToken? {
        let source = CancellationSource()
        let result = withState { state -> (accepted: Bool, previousSource: CancellationSource?) in
            guard admittedDuringLifecycle
                || Self.ordinaryHardwareIOIsAdmitted(state) else {
                return (false, nil)
            }
            let previousSource = state[keyPath: cancellationSource]
            state[keyPath: cancellationSource] = source
            state[keyPath: cache] = nil
            mutateState(&state)
            updateCoordinator(source.token)
            return (true, previousSource)
        }
        guard result.accepted else {
            return nil
        }
        result.previousSource?.cancel()
        return source.token
    }

    @discardableResult
    private func runFeatureOperation<Feature>(
        cache: WritableKeyPath<State, FeatureAccess<Feature>?>,
        cancellationSource: WritableKeyPath<State, CancellationSource>,
        coordinator: HardwareSettingApplyCoordinator,
        operation: @escaping (CancellationToken) -> Void,
        onCancelled: @escaping () -> Void
    ) -> CancellationToken {
        guard let token = resetFeatureOperation(
            cache: cache,
            cancellationSource: cancellationSource,
            updateCoordinator: { _ in coordinator.cancel() }
        ) else {
            let token = Self.cancelledToken()
            onCancelled()
            return token
        }
        let guardedOperation = {
            let mutationIsAdmitted = self.withState {
                Self.ordinaryHardwareIOIsAdmitted($0)
            }
            guard token.shouldContinue, mutationIsAdmitted else {
                onCancelled()
                return
            }
            operation(token)
        }
        perform(guardedOperation)
        return token
    }

    private static func cancelledToken() -> CancellationToken {
        let source = CancellationSource()
        source.cancel()
        return source.token
    }

    private static func ordinaryHardwareIOIsAdmitted(_ state: State) -> Bool {
        state.lifecycleOwner == nil
            && state.ordinaryHardwareAccess.token.shouldContinue
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

        let previousSerial = LogitechStableSerial.normalize(previous.identity.serialNumber)
        let currentSerial = LogitechStableSerial.normalize(current.identity.serialNumber)
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
        if let initialSerial = LogitechStableSerial.normalize(initialRoute.identity.serialNumber) {
            guard let currentSerial = LogitechStableSerial.normalize(currentRoute.identity.serialNumber) else {
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
