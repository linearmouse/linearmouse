// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import os.log

/// Inverts the vertical wheel inside the mouse through the invert bit of the
/// HID++ Hi-Res Wheel feature (0x2121). Unlike reverse scrolling, the device
/// itself reports the inverted direction, so the setting also applies on other
/// hosts the mouse controls, such as an iPad reached through Universal Control.
///
/// The bit lives in the same mode byte as high resolution. Every write reads
/// the byte first and changes only its own bit, so the two settings never
/// overwrite each other. Both run on the device's serial Logitech queue.
extension Device {
    private static let logitechWheelInvertLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "WheelInvert"
    )

    var isLogitechWheelInvertApplyRunning: Bool {
        logitechSession.isWheelInvertApplyRunning
    }

    var confirmedLogitechWheelInvert: Bool? {
        logitechSession.wheelInverted
    }

    var needsLogitechWheelInvertRestoreRetry: Bool {
        logitechSession.needsWheelInvertRestoreRetry
    }

    func logitechWheelInvert(
        for token: CancellationToken,
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechDeviceSession.FeatureAccess<HiResWheel>? {
        logitechSession.wheelInvert(expectedToken: token) { [weak self] route, token in
            guard let self else {
                return nil
            }

            let transportShouldContinue = { [weak self] in
                token.shouldContinue
                    && self?.isRemoved == false
            }
            guard let target = LogitechHIDPPFeatureTargetResolver.resolve(
                .hiresWheel,
                for: pointerDevice,
                receiverSlot: route?.slot ?? logitechSession.wheelInvertReceiverSlotSnapshot,
                requestDeadline: deadline,
                requestShouldContinue: operationShouldContinue,
                shouldContinue: transportShouldContinue
            ) else {
                return nil
            }
            let feature = HiResWheel(
                transport: target.transport,
                featureIndex: target.featureIndex
            )
            return .init(
                feature: feature,
                stableTargetKey: logitechHardwareTargetKey(
                    for: route,
                    receiverSlot: feature.receiverSlot
                ),
                receiverSlot: feature.receiverSlot
            )
        }
    }

    func applyConfiguredWheelInvert(_ inverted: Bool) {
        logitechSession.startWheelInvertApply { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let start = Date()
            let applied = applyWheelInvertSynchronously(
                inverted,
                expectedToken: token,
                verifiesCachedValue: attempt.verifiesCachedValue,
                until: attempt.shouldContinue
            )
            guard !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let phase = attempt.verifiesCachedValue ? "verification" : "apply"
            let duration = Date().timeIntervalSince(start)
            let slot = logitechReceiverRouteSnapshot.map { String($0.slot) } ?? "direct"
            if applied != nil {
                os_log(
                    "Logitech wheel invert %{public}@ succeeded: inverted=%{public}@ device=%{public}@ slot=%{public}@ attempt=%{public}d duration=%{public}.3f",
                    log: Self.logitechWheelInvertLog,
                    type: .info,
                    phase,
                    inverted ? "true" : "false",
                    name,
                    slot,
                    attempt.number,
                    duration
                )
                return true
            }

            os_log(
                "Logitech wheel invert %{public}@ attempt failed: inverted=%{public}@ device=%{public}@ slot=%{public}@ attempt=%{public}d final=%{public}@ duration=%{public}.3f",
                log: Self.logitechWheelInvertLog,
                type: attempt.isFinal ? .error : .info,
                phase,
                inverted ? "true" : "false",
                name,
                slot,
                attempt.number,
                attempt.isFinal ? "true" : "false",
                duration
            )
            return false
        }
    }

    private func applyWheelInvertSynchronously(
        _ inverted: Bool,
        expectedToken: CancellationToken,
        verifiesCachedValue: Bool,
        until operationShouldContinue: @escaping () -> Bool
    ) -> Bool? {
        let operationIsAdmitted = {
            operationShouldContinue()
                && self.logitechSession.allowsConfiguredWheelInvertOperation(for: expectedToken)
        }
        guard !isRemoved,
              let access = logitechWheelInvert(
                  for: expectedToken,
                  until: operationIsAdmitted
              ) else {
            return nil
        }

        let controller = access.feature
        let writeIsAdmitted = {
            operationIsAdmitted()
                && self.logitechSession.allowsConfiguredWheelInvertWrite(for: access)
        }

        _ = seedStoredWheelInvertBaseline(receiverSlot: controller.receiverSlot)
        // Capture before every possible write. A device may apply a change
        // even when its acknowledgement is lost.
        guard LogitechHiResBaselineCapture.ensureCaptured(
            hasInitialState: { logitechSession.hasInitialWheelInvertState },
            readCurrentMode: { controller.isWheelInverted(until: writeIsAdmitted) },
            capture: { recordWheelInvertBaseline(inverted: $0, for: access) }
        ), logitechSession.initialWheelInverted(for: access) != nil else {
            return nil
        }

        if logitechSession.wheelInverted == inverted, !verifiesCachedValue {
            return inverted
        }
        if verifiesCachedValue || logitechSession.wheelInverted == nil,
           let current = controller.isWheelInverted(until: writeIsAdmitted) {
            logitechSession.updateWheelInverted(current, for: access)
            if current == inverted {
                return current
            }
        }

        guard let applied = controller.setWheelInverted(inverted, until: writeIsAdmitted) else {
            return nil
        }
        logitechSession.updateWheelInverted(applied, for: access)

        // A write reply is advisory, and firmware may reset the mode while it
        // wakes. Leave success to the coordinator's delayed verification read.
        return verifiesCachedValue || applied != inverted ? nil : applied
    }

    /// Stops managing the wheel direction at runtime. Failed attempts retain
    /// the original target-bound state so a later reconciliation or teardown
    /// can retry it.
    func stopManagingWheelInvert() {
        logitechSession.startWheelInvertRestore { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }
            return restoreWheelInvertSynchronously(
                expectedToken: token,
                until: attempt.shouldContinue
            )
        }
    }

    func prepareWheelInvertForReconnect() {
        logitechSession.cancelWheelInvertApply()
        logitechSession.clearWheelInverted()
    }

    /// Synchronous only with respect to the Logitech session queue. The
    /// terminal coordinator invokes it from that background queue.
    @discardableResult
    func restoreWheelInvertForTeardown(
        expectedToken: CancellationToken,
        attempt: LogitechTerminalHardwareRestoreRetry.Attempt
    ) -> Bool {
        let shouldContinue = attempt.shouldContinue
        let restored = restoreWheelInvertSynchronously(
            expectedToken: expectedToken,
            deadline: attempt.deadline,
            until: shouldContinue
        ) { _ in shouldContinue() }
        if !restored {
            // Force the next bounded attempt to bind a fresh feature to the
            // current channel, keeping the baseline and token.
            logitechSession.invalidateWheelInvert(for: expectedToken)
        }
        return restored
    }

    private func restoreWheelInvertSynchronously(
        expectedToken: CancellationToken,
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool = { true },
        writeAdmission: ((LogitechDeviceSession.FeatureAccess<HiResWheel>) -> Bool)? = nil
    ) -> Bool {
        let shouldContinue = {
            expectedToken.shouldContinue
                && operationShouldContinue()
                && !self.isRemoved
                && deadline.map { Date() < $0 } != false
        }
        guard shouldContinue() else {
            return false
        }
        let isBoundedLifecycleRestore = writeAdmission != nil
        let featureIOShouldContinue = {
            shouldContinue()
                && (isBoundedLifecycleRestore
                    || self.logitechSession.allowsConfiguredWheelInvertOperation(for: expectedToken))
        }

        let hasKnownBaseline = seedStoredWheelInvertBaseline(
            receiverSlot: logitechReceiverRouteSnapshot?.slot
        )
        guard logitechSession.hasInitialWheelInvertState || hasKnownBaseline else {
            logitechSession.invalidateWheelInvert(for: expectedToken)
            logitechSession.clearWheelInverted()
            return true
        }

        guard !isRemoved,
              let access = logitechWheelInvert(
                  for: expectedToken,
                  deadline: deadline,
                  until: featureIOShouldContinue
              ),
              let initialInverted = logitechSession.initialWheelInverted(for: access)
        else {
            logitechSession.invalidateWheelInvert(for: expectedToken)
            return false
        }
        _ = seedStoredWheelInvertBaseline(receiverSlot: access.feature.receiverSlot)

        let writeIsAdmitted = {
            shouldContinue()
                && (writeAdmission?(access)
                    ?? self.logitechSession.allowsConfiguredWheelInvertWrite(for: access))
        }
        guard LogitechHiResRestoreOperation.perform(
            initialEnabled: initialInverted,
            shouldContinue: shouldContinue,
            readCurrentMode: {
                access.feature.isWheelInverted(deadline: deadline, until: featureIOShouldContinue)
            },
            writeMode: {
                _ = access.feature.setWheelInverted($0, deadline: deadline, until: writeIsAdmitted)
            }
        ) else {
            return false
        }

        let commit = logitechSession.completeWheelInvertRestore(inverted: initialInverted, for: access)
        guard case let .committed(handle) = commit else {
            return false
        }
        if let handle {
            logitechHardwareBaselineStore?.consumeWheelInvertBaseline(handle)
        }
        return true
    }

    @discardableResult
    private func seedStoredWheelInvertBaseline(receiverSlot: UInt8?) -> Bool {
        guard let lease = logitechSession.wheelInvertTargetLease(
                  receiverSlot: receiverSlot,
                  stableTargetKey: { [weak self] route, slot in
                      self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
                  }
              ),
              let target = lease.stableTargetKey,
              let claim = logitechHardwareBaselineStore?.wheelInvertBaseline(for: target) else {
            return false
        }
        _ = logitechSession.seedInitialWheelInvertState(claim, for: lease)
        return true
    }

    private func recordWheelInvertBaseline(
        inverted: Bool,
        for access: LogitechDeviceSession.FeatureAccess<HiResWheel>
    ) {
        _ = logitechSession.recordInitialWheelInvertState(inverted: inverted, for: access)
        // Discovery may enrich serial metadata while the HID read is in
        // flight, so promotion always uses a freshly validated lease.
        promoteWheelInvertBaselineIfPossible()
    }

    func promoteWheelInvertBaselineIfPossible() {
        guard let store = logitechHardwareBaselineStore,
              let lease = logitechSession.wheelInvertTargetLease(
                  receiverSlot: nil,
                  stableTargetKey: { [weak self] route, slot in
                      self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
                  }
              ),
              let promotion = logitechSession.wheelInvertBaselinePromotion(for: lease)
        else {
            return
        }

        let claim = store.captureWheelInvertBaseline(
            inverted: promotion.inverted,
            for: promotion.target
        )
        _ = logitechSession.attachWheelInvertBaseline(claim, to: promotion)
    }
}
