// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP

final class LogitechDeviceSession {
    /// A controller bound to the cancellation token that created its HID++ transport.
    /// Superseded operations cannot use a controller from a newer device session.
    struct FeatureAccess<Feature> {
        let feature: Feature
        fileprivate let token: CancellationToken
    }

    private struct InitialHiResWheelState {
        let route: LogitechReceiverRoute?
        let enabled: Bool
    }

    private struct State {
        var discovery: LogitechReceiverDiscovery?
        var adjustableDPI: AdjustableDPI?
        var hiResWheel: HiResWheel?
        var dpiCancellationSource = CancellationSource()
        var hiResWheelCancellationSource = CancellationSource()
        var sensorDPI: Int?
        var hiResWheelEnabled: Bool?
        var hiResWheelMultiplier: Int?
        var initialHiResWheelState: InitialHiResWheelState?
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
            let hardwareTargetChanged = LogitechReceiverRoute.hardwareTargetChanged(
                from: previousDiscovery?.route,
                to: discovery?.route
            )
            let candidateAvailabilityChanged = previousDiscovery?.identities.isEmpty
                != discovery?.identities.isEmpty
            state.discovery = discovery
            if let initialState = state.initialHiResWheelState,
               let route = discovery?.route,
               LogitechReceiverRoute.hardwareTargetChanged(from: initialState.route, to: route) {
                state.initialHiResWheelState = nil
            }

            guard hardwareTargetChanged else {
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
            coordinator.start { attempt in operation(attempt, token) }
        }
    }

    func cancelDPIApply() {
        let coordinator = dpiApplyCoordinator
        resetFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource
        ) { _ in coordinator.cancel() }
    }

    func runDPIOperation(_ operation: @escaping (CancellationToken) -> Void) {
        runFeatureOperation(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            coordinator: dpiApplyCoordinator,
            waitUntilFinished: false,
            operation: operation
        )
    }

    func startHiResWheelApply(
        _ operation: @escaping (HardwareSettingApplyCoordinator.Attempt, CancellationToken) -> Bool
    ) {
        let coordinator = hiResWheelApplyCoordinator
        resetFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource
        ) { token in
            coordinator.start { attempt in operation(attempt, token) }
        }
    }

    func cancelHiResWheelApply() {
        let coordinator = hiResWheelApplyCoordinator
        resetFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource
        ) { _ in coordinator.cancel() }
    }

    func runHiResWheelOperation(
        waitUntilFinished: Bool,
        _ operation: @escaping (CancellationToken) -> Void
    ) {
        runFeatureOperation(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource,
            coordinator: hiResWheelApplyCoordinator,
            waitUntilFinished: waitUntilFinished,
            operation: operation
        )
    }

    func updateSensorDPI(_ dpi: Int, for access: FeatureAccess<AdjustableDPI>) {
        withState { state in
            guard state.dpiCancellationSource.token == access.token,
                  access.token.shouldContinue else {
                return
            }
            state.sensorDPI = dpi
        }
    }

    func clearSensorDPI() {
        withState { $0.sensorDPI = nil }
    }

    func updateHiResWheelState(
        enabled: Bool?,
        multiplier: Int?,
        for access: FeatureAccess<HiResWheel>
    ) {
        withState { state in
            guard state.hiResWheelCancellationSource.token == access.token,
                  access.token.shouldContinue else {
                return
            }
            state.hiResWheelEnabled = enabled
            state.hiResWheelMultiplier = enabled == true ? multiplier : nil
        }
    }

    func recordInitialHiResWheelState(enabled: Bool, for access: FeatureAccess<HiResWheel>) {
        withState { state in
            guard state.hiResWheelCancellationSource.token == access.token,
                  access.token.shouldContinue,
                  state.initialHiResWheelState == nil else {
                return
            }
            state.initialHiResWheelState = .init(
                route: state.discovery?.route,
                enabled: enabled
            )
        }
    }

    func initialHiResWheelEnabled(requiresReceiverRoute: Bool) -> Bool? {
        withState { state in
            guard let initialState = state.initialHiResWheelState else {
                return nil
            }

            let currentRoute = state.discovery?.route
            if requiresReceiverRoute, currentRoute == nil {
                return nil
            }
            guard !LogitechReceiverRoute.hardwareTargetChanged(
                from: initialState.route,
                to: currentRoute
            ) else {
                return nil
            }
            return initialState.enabled
        }
    }

    func clearHiResWheelState(includingInitialState: Bool) {
        withState {
            $0.hiResWheelEnabled = nil
            $0.hiResWheelMultiplier = nil
            if includingInitialState {
                $0.initialHiResWheelState = nil
            }
        }
    }

    private func resetFeatureOperation<Feature>(
        cache: WritableKeyPath<State, Feature?>,
        cancellationSource: WritableKeyPath<State, CancellationSource>,
        updateCoordinator: (CancellationToken) -> Void
    ) -> CancellationToken {
        let source = CancellationSource()
        let previousSource = withState { state -> CancellationSource in
            let previousSource = state[keyPath: cancellationSource]
            state[keyPath: cancellationSource] = source
            state[keyPath: cache] = nil
            updateCoordinator(source.token)
            return previousSource
        }
        previousSource.cancel()
        return source.token
    }

    private func runFeatureOperation<Feature>(
        cache: WritableKeyPath<State, Feature?>,
        cancellationSource: WritableKeyPath<State, CancellationSource>,
        coordinator: HardwareSettingApplyCoordinator,
        waitUntilFinished: Bool,
        operation: @escaping (CancellationToken) -> Void
    ) {
        let token = resetFeatureOperation(
            cache: cache,
            cancellationSource: cancellationSource
        ) { _ in coordinator.cancel() }
        let guardedOperation = {
            guard token.shouldContinue else {
                return
            }
            operation(token)
        }
        if waitUntilFinished {
            performSynchronously(guardedOperation)
        } else {
            perform(guardedOperation)
        }
    }

    func invalidateHiResWheel() {
        withState { $0.hiResWheel = nil }
    }

    func adjustableDPI(
        expectedToken: CancellationToken? = nil,
        create: (LogitechReceiverRoute?, CancellationToken) -> AdjustableDPI?
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
        create: (LogitechReceiverRoute?, CancellationToken) -> HiResWheel?
    ) -> FeatureAccess<HiResWheel>? {
        feature(
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
        cache: WritableKeyPath<State, Feature?>,
        cancellationSource: KeyPath<State, CancellationSource>,
        expectedToken: CancellationToken?,
        create: (LogitechReceiverRoute?, CancellationToken) -> Feature?
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
            return .init(feature: cached, token: snapshot.token)
        }

        guard let feature = create(snapshot.route, snapshot.token)
        else {
            return nil
        }

        return withState { state in
            let currentToken = state[keyPath: cancellationSource].token
            guard currentToken == snapshot.token, currentToken.shouldContinue else {
                return nil
            }

            state[keyPath: cache] = feature
            return .init(feature: feature, token: currentToken)
        }
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
