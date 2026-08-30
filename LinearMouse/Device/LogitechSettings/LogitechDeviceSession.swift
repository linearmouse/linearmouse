// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP

final class LogitechDeviceSession {
    struct State {
        var discovery: LogitechReceiverDiscovery?
        var adjustableDPI: AdjustableDPI?
        var hiResWheel: HiResWheel?
        var dpiCancellationSource = CancellationSource()
        var hiResWheelCancellationSource = CancellationSource()
        var sensorDPI: Int?
        var hiResWheelEnabled: Bool?
        var hiResWheelMultiplier: Int?
        var initialHiResWheelEnabled: Bool?
    }

    struct DiscoveryUpdate {
        let hardwareTargetChanged: Bool
        let candidateAvailabilityChanged: Bool
        let hasCandidates: Bool
    }

    let queue: DispatchQueue
    private let lock = NSLock()
    private var state = State()

    lazy var dpiApplyCoordinator = makeApplyCoordinator()
    lazy var hiResWheelApplyCoordinator = makeApplyCoordinator()

    init(deviceID: Int32) {
        queue = DispatchQueue(
            label: "app.linearmouse.logitech-settings.\(deviceID)",
            qos: .default
        )
    }

    func withState<T>(_ body: (inout State) throws -> T) rethrows -> T {
        try lock.withLock { try body(&state) }
    }

    var discoverySnapshot: LogitechReceiverDiscovery? {
        withState { $0.discovery }
    }

    func updateDiscovery(_ discovery: LogitechReceiverDiscovery?) -> DiscoveryUpdate {
        let update = withState { state -> (DiscoveryUpdate, CancellationSource?, CancellationSource?) in
            let previousDiscovery = state.discovery
            let hardwareTargetChanged = LogitechReceiverRoute.hardwareTargetChanged(
                from: previousDiscovery?.route,
                to: discovery?.route
            )
            let candidateAvailabilityChanged = previousDiscovery?.identities.isEmpty
                != discovery?.identities.isEmpty
            state.discovery = discovery

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
        if update.0.hardwareTargetChanged {
            dpiApplyCoordinator.cancel()
            hiResWheelApplyCoordinator.cancel()
        }
        return update.0
    }

    func renewDPITransport() {
        let previousSource = withState { state -> CancellationSource in
            let source = state.dpiCancellationSource
            state.dpiCancellationSource = CancellationSource()
            state.adjustableDPI = nil
            return source
        }
        previousSource.cancel()
    }

    func renewHiResWheelTransport() {
        let previousSource = withState { state -> CancellationSource in
            let source = state.hiResWheelCancellationSource
            state.hiResWheelCancellationSource = CancellationSource()
            state.hiResWheel = nil
            return source
        }
        previousSource.cancel()
    }

    func invalidateHiResWheel() {
        withState { $0.hiResWheel = nil }
    }

    func adjustableDPI(
        create: (LogitechReceiverRoute?, CancellationToken) -> AdjustableDPI?
    ) -> AdjustableDPI? {
        feature(
            cache: \State.adjustableDPI,
            cancellationSource: \State.dpiCancellationSource,
            create: create
        )
    }

    func hiResWheel(
        create: (LogitechReceiverRoute?, CancellationToken) -> HiResWheel?
    ) -> HiResWheel? {
        feature(
            cache: \State.hiResWheel,
            cancellationSource: \State.hiResWheelCancellationSource,
            create: create
        )
    }

    func cancelAll() {
        dpiApplyCoordinator.cancel()
        hiResWheelApplyCoordinator.cancel()
        let sources = withState { state -> (CancellationSource, CancellationSource) in
            let sources = (state.dpiCancellationSource, state.hiResWheelCancellationSource)
            state = State()
            return sources
        }
        sources.0.cancel()
        sources.1.cancel()
    }

    private func feature<Feature>(
        cache: WritableKeyPath<State, Feature?>,
        cancellationSource: KeyPath<State, CancellationSource>,
        create: (LogitechReceiverRoute?, CancellationToken) -> Feature?
    ) -> Feature? {
        let snapshot = withState { state in
            (
                cached: state[keyPath: cache],
                route: state.discovery?.route,
                token: state[keyPath: cancellationSource].token
            )
        }
        if let cached = snapshot.cached {
            return cached
        }

        guard snapshot.token.shouldContinue,
              let feature = create(snapshot.route, snapshot.token)
        else {
            return nil
        }

        return withState { state in
            let currentToken = state[keyPath: cancellationSource].token
            guard currentToken == snapshot.token, currentToken.shouldContinue else {
                return nil
            }

            state[keyPath: cache] = feature
            return feature
        }
    }

    private func makeApplyCoordinator() -> HardwareSettingApplyCoordinator {
        HardwareSettingApplyCoordinator { [weak self] delay, work in
            guard let self else {
                return
            }

            let workItem = DispatchWorkItem(block: work)
            if delay <= 0 {
                queue.async(execute: workItem)
            } else {
                queue.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }
}
