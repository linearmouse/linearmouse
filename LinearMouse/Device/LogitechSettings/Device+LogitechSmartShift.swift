// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import os.log

/// SmartShift fields that LinearMouse writes and must later restore.
struct LogitechSmartShiftFields: OptionSet, Hashable {
    let rawValue: UInt8

    static let wheelMode = Self(rawValue: 1 << 0)
    static let autoDisengage = Self(rawValue: 1 << 1)
    static let torque = Self(rawValue: 1 << 2)

    /// Builds the write that returns `fields` to `baseline`. A torque the
    /// baseline did not report cannot be restored and is left alone.
    static func restoreChange(_ fields: Self, from baseline: SmartShift.Status) -> SmartShift.Change {
        SmartShift.Change(
            wheelMode: fields.contains(.wheelMode) ? baseline.wheelMode : nil,
            autoDisengage: fields.contains(.autoDisengage) ? baseline.autoDisengage : nil,
            torque: fields.contains(.torque) ? baseline.torque : nil
        )
    }

    static func restore(_ fields: Self, from baseline: SmartShift.Status, matches status: SmartShift.Status) -> Bool {
        restoreChange(fields, from: baseline).isSatisfied(by: status)
    }
}

extension SmartShift.Change {
    func isSatisfied(by status: SmartShift.Status) -> Bool {
        wheelMode.map { $0 == status.wheelMode } != false
            && autoDisengage.map { $0 == status.autoDisengage } != false
            && torque.map { $0 == status.torque } != false
    }
}

/// The SmartShift state requested by a scheme, clamped to the wire ranges.
struct LogitechSmartShiftTarget: Equatable {
    let wheelMode: SmartShift.WheelMode?
    let autoDisengage: UInt8?
    let torque: UInt8?

    init?(_ configuration: Scheme.Logitech.SmartShift?) {
        guard let configuration, !configuration.isEmpty else {
            return nil
        }

        wheelMode = configuration.mode.map {
            switch $0 {
            case .ratchet:
                .ratchet
            case .freeSpin:
                .freeSpin
            }
        }
        autoDisengage = configuration.autoDisengage.map {
            switch $0 {
            case let .threshold(threshold):
                UInt8(threshold.clamped(to: Scheme.Logitech.SmartShift.thresholdRange))
            case .never:
                SmartShift.permanentRatchet
            }
        }
        torque = configuration.torque.map {
            UInt8($0.clamped(to: Scheme.Logitech.SmartShift.torqueRange))
        }
    }

    /// The fields this target writes on a wheel. Torque counts only when the
    /// wheel advertises tunable torque.
    func fields(supportsTunableTorque: Bool) -> LogitechSmartShiftFields {
        var fields: LogitechSmartShiftFields = []
        if wheelMode != nil {
            fields.insert(.wheelMode)
        }
        if autoDisengage != nil {
            fields.insert(.autoDisengage)
        }
        if torque != nil, supportsTunableTorque {
            fields.insert(.torque)
        }
        return fields
    }

    /// The write that applies this target, returning any field LinearMouse
    /// managed earlier but no longer configures to its original value.
    func change(
        supportsTunableTorque: Bool,
        managedFields: LogitechSmartShiftFields,
        baseline: SmartShift.Status
    ) -> SmartShift.Change {
        let fields = fields(supportsTunableTorque: supportsTunableTorque)
        var change = LogitechSmartShiftFields.restoreChange(
            managedFields.subtracting(fields),
            from: baseline
        )
        if let wheelMode {
            change.wheelMode = wheelMode
        }
        if let autoDisengage {
            change.autoDisengage = autoDisengage
        }
        if fields.contains(.torque) {
            change.torque = torque
        }
        return change
    }
}

enum LogitechSmartShiftBaselineCapture {
    /// A write is admitted only after the original wheel state is already
    /// known or a fresh pre-write read has been accepted by the current lease.
    static func ensureCaptured(
        hasInitialState: () -> Bool,
        readCurrentStatus: () -> SmartShift.Status?,
        record: (SmartShift.Status) -> Void
    ) -> Bool {
        if hasInitialState() {
            return true
        }
        guard let status = readCurrentStatus() else {
            return false
        }
        record(status)
        return hasInitialState()
    }
}

enum LogitechSmartShiftRestoreOperation {
    /// A write acknowledgement is advisory. Only a subsequent read (or the
    /// initial read when no write is needed) confirms restoration. Returns the
    /// confirmed status.
    static func perform(
        change: SmartShift.Change,
        shouldContinue: () -> Bool,
        readCurrentStatus: () -> SmartShift.Status?,
        write: (SmartShift.Change) -> Void
    ) -> SmartShift.Status? {
        guard shouldContinue() else {
            return nil
        }
        var status = readCurrentStatus()
        if let current = status, change.isSatisfied(by: current) {
            return shouldContinue() ? current : nil
        }
        guard shouldContinue() else {
            return nil
        }
        write(change)
        guard shouldContinue() else {
            return nil
        }
        status = readCurrentStatus()
        guard shouldContinue(), let status, change.isSatisfied(by: status) else {
            return nil
        }
        return status
    }
}

extension Device {
    private static let logitechSmartShiftLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "SmartShift"
    )

    struct SmartShiftInfo: Equatable {
        let supportsSmartShift: Bool
        let supportsTunableTorque: Bool
        let defaultAutoDisengage: UInt8?
        let status: SmartShift.Status?
    }

    var isLogitechSmartShiftApplyRunning: Bool {
        logitechSession.isSmartShiftApplyRunning
    }

    var needsLogitechSmartShiftRestoreRetry: Bool {
        logitechSession.needsSmartShiftRestoreRetry
    }

    /// Uses cached state only; diffing a configuration must not query HID++.
    func hasConfirmedLogitechSmartShift(_ target: LogitechSmartShiftTarget) -> Bool {
        guard let confirmed = logitechSession.confirmedSmartShift else {
            return false
        }
        return target.change(
            supportsTunableTorque: confirmed.supportsTunableTorque,
            managedFields: [],
            baseline: confirmed.status
        )
        .isSatisfied(by: confirmed.status)
    }

    func logitechSmartShift(
        for token: CancellationToken,
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechDeviceSession.FeatureAccess<SmartShift>? {
        logitechSmartShift(
            expectedToken: token,
            requestDeadline: deadline,
            operationShouldContinue: operationShouldContinue
        )
    }

    func logitechSmartShift(
        expectedToken: CancellationToken?,
        requestDeadline: Date? = nil,
        operationShouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechDeviceSession.FeatureAccess<SmartShift>? {
        logitechSession.smartShift(expectedToken: expectedToken) { [weak self] route, token in
            guard let self else {
                return nil
            }

            let transportShouldContinue = { [weak self] in
                token.shouldContinue
                    && self?.isRemoved == false
            }
            // Wheels expose one variant: the enhanced feature on newer mice,
            // the original one on older mice such as the MX Master 2S.
            for variant in [SmartShift.Variant.enhanced, .standard] {
                guard let target = LogitechHIDPPFeatureTargetResolver.resolve(
                    variant.featureID,
                    for: pointerDevice,
                    receiverSlot: route?.slot ?? logitechSession.smartShiftReceiverSlotSnapshot,
                    requestDeadline: requestDeadline,
                    requestShouldContinue: operationShouldContinue,
                    shouldContinue: transportShouldContinue
                ) else {
                    continue
                }
                guard let feature = SmartShift(
                    transport: target.transport,
                    featureIndex: target.featureIndex,
                    variant: variant,
                    deadline: requestDeadline,
                    until: operationShouldContinue
                ) else {
                    return nil
                }
                return .init(
                    feature: feature,
                    stableTargetKey: logitechHardwareTargetKey(
                        for: route,
                        receiverSlot: feature.receiverSlot
                    ),
                    receiverSlot: feature.receiverSlot
                )
            }
            return nil
        }
    }

    func applyConfiguredSmartShift(_ target: LogitechSmartShiftTarget) {
        logitechSession.startSmartShiftApply { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }

            let start = Date()
            let applied = applySmartShiftSynchronously(
                target,
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
            if let applied {
                os_log(
                    "Logitech SmartShift %{public}@ succeeded: mode=%{public}d autoDisengage=%{public}d torque=%{public}d device=%{public}@ slot=%{public}@ attempt=%{public}d duration=%{public}.3f",
                    log: Self.logitechSmartShiftLog,
                    type: .info,
                    phase,
                    applied.wheelMode.rawValue,
                    applied.autoDisengage,
                    applied.torque ?? 0,
                    name,
                    slot,
                    attempt.number,
                    duration
                )
                return true
            }

            os_log(
                "Logitech SmartShift %{public}@ attempt failed: device=%{public}@ slot=%{public}@ attempt=%{public}d final=%{public}@ duration=%{public}.3f",
                log: Self.logitechSmartShiftLog,
                type: attempt.isFinal ? .error : .info,
                phase,
                name,
                slot,
                attempt.number,
                attempt.isFinal ? "true" : "false",
                duration
            )
            return false
        }
    }

    func refreshSmartShiftInfo(completion: @escaping (SmartShiftInfo) -> Void) {
        let deadline = Date().addingTimeInterval(Self.logitechOrdinaryReadTimeout)
        let deliver: (SmartShiftInfo) -> Void = { info in
            DispatchQueue.main.async {
                completion(info)
            }
        }
        logitechSession.runBoundedOrdinaryHardwareRead(deadline: deadline) { shouldContinue in
            deliver(self.smartShiftInfo(deadline: deadline, until: shouldContinue))
        } onCancelled: {
            deliver(self.unsupportedSmartShiftInfo)
        }
    }

    private var unsupportedSmartShiftInfo: SmartShiftInfo {
        SmartShiftInfo(
            supportsSmartShift: false,
            supportsTunableTorque: false,
            defaultAutoDisengage: nil,
            status: nil
        )
    }

    private func smartShiftInfo(
        deadline: Date,
        until shouldContinue: @escaping () -> Bool
    ) -> SmartShiftInfo {
        guard !isRemoved,
              shouldContinue(),
              let access = logitechSmartShift(
                  expectedToken: nil,
                  requestDeadline: deadline,
                  operationShouldContinue: shouldContinue
              ) else {
            return unsupportedSmartShiftInfo
        }

        let status = access.feature.status(deadline: deadline, until: shouldContinue)
        if let status {
            logitechSession.updateSmartShiftStatus(status, for: access)
        }
        return SmartShiftInfo(
            supportsSmartShift: true,
            supportsTunableTorque: access.feature.supportsTunableTorque,
            defaultAutoDisengage: access.feature.defaultAutoDisengage,
            status: status
        )
    }

    private func applySmartShiftSynchronously(
        _ target: LogitechSmartShiftTarget,
        expectedToken: CancellationToken,
        verifiesCachedValue: Bool,
        until operationShouldContinue: @escaping () -> Bool
    ) -> SmartShift.Status? {
        let operationIsAdmitted = {
            operationShouldContinue()
                && self.logitechSession.allowsConfiguredSmartShiftOperation(for: expectedToken)
        }
        guard !isRemoved,
              let access = logitechSmartShift(
                  for: expectedToken,
                  until: operationIsAdmitted
              ) else {
            return nil
        }

        let controller = access.feature
        let writeIsAdmitted = {
            operationIsAdmitted()
                && self.logitechSession.allowsConfiguredSmartShiftWrite(for: access)
        }

        _ = seedStoredSmartShiftBaseline(receiverSlot: controller.receiverSlot)
        // Capture before every possible write. A device may apply a change
        // even when its acknowledgement is lost.
        guard LogitechSmartShiftBaselineCapture.ensureCaptured(
            hasInitialState: { logitechSession.hasInitialSmartShiftState },
            readCurrentStatus: { controller.status(until: writeIsAdmitted) },
            record: { recordSmartShiftBaseline($0, for: access) }
        ), let baseline = logitechSession.initialSmartShiftStatus(for: access) else {
            return nil
        }

        let change = target.change(
            supportsTunableTorque: controller.supportsTunableTorque,
            managedFields: logitechSession.smartShiftManagedFields,
            baseline: baseline
        )

        if let cachedStatus = logitechSession.smartShiftStatus,
           change.isSatisfied(by: cachedStatus),
           !verifiesCachedValue {
            return cachedStatus
        }
        if verifiesCachedValue || logitechSession.smartShiftStatus == nil,
           let currentStatus = controller.status(until: writeIsAdmitted) {
            logitechSession.updateSmartShiftStatus(currentStatus, for: access)
            if change.isSatisfied(by: currentStatus) {
                return currentStatus
            }
        }

        guard !change.isEmpty else {
            return logitechSession.smartShiftStatus
        }
        recordSmartShiftManagedFields(
            target.fields(supportsTunableTorque: controller.supportsTunableTorque),
            for: access
        )
        guard let reply = controller.apply(change, until: writeIsAdmitted) else {
            return nil
        }
        logitechSession.updateSmartShiftStatus(reply, for: access)

        // A write reply is advisory, and firmware may reset the wheel while it
        // wakes. Leave success to the coordinator's delayed verification read.
        return verifiesCachedValue || !change.isSatisfied(by: reply) ? nil : reply
    }

    /// Stops managing SmartShift at runtime. Failed attempts retain the
    /// original target-bound state so a later reconciliation or teardown can
    /// retry it.
    func stopManagingSmartShift() {
        logitechSession.startSmartShiftRestore { [weak self] attempt, token in
            guard let self, !isRemoved, attempt.shouldContinue() else {
                return false
            }
            return restoreSmartShiftSynchronously(
                expectedToken: token,
                until: attempt.shouldContinue
            )
        }
    }

    func prepareSmartShiftForReconnect() {
        logitechSession.cancelSmartShiftApply()
        logitechSession.clearSmartShiftStatus()
    }

    /// Synchronous only with respect to the Logitech session queue. The
    /// terminal coordinator invokes it from that background queue.
    @discardableResult
    func restoreSmartShiftForTeardown(
        expectedToken: CancellationToken,
        attempt: LogitechTerminalHardwareRestoreRetry.Attempt
    ) -> Bool {
        let shouldContinue = attempt.shouldContinue
        let restored = restoreSmartShiftSynchronously(
            expectedToken: expectedToken,
            deadline: attempt.deadline,
            until: shouldContinue
        ) { _ in shouldContinue() }
        if !restored {
            // Force the next bounded attempt to bind a fresh feature to the
            // current channel, keeping the baseline and token.
            logitechSession.invalidateSmartShift(for: expectedToken)
        }
        return restored
    }

    private func restoreSmartShiftSynchronously(
        expectedToken: CancellationToken,
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool = { true },
        writeAdmission: ((LogitechDeviceSession.FeatureAccess<SmartShift>) -> Bool)? = nil
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
                    || self.logitechSession.allowsConfiguredSmartShiftOperation(for: expectedToken))
        }

        let hasKnownBaseline = seedStoredSmartShiftBaseline(
            receiverSlot: logitechReceiverRouteSnapshot?.slot
        )
        guard logitechSession.hasInitialSmartShiftState || hasKnownBaseline else {
            logitechSession.invalidateSmartShift(for: expectedToken)
            logitechSession.clearSmartShiftStatus()
            return true
        }

        guard !isRemoved,
              let access = logitechSmartShift(
                  for: expectedToken,
                  deadline: deadline,
                  until: featureIOShouldContinue
              ),
              let baseline = logitechSession.initialSmartShiftStatus(for: access)
        else {
            logitechSession.invalidateSmartShift(for: expectedToken)
            return false
        }
        _ = seedStoredSmartShiftBaseline(receiverSlot: access.feature.receiverSlot)

        let writeIsAdmitted = {
            shouldContinue()
                && (writeAdmission?(access)
                    ?? self.logitechSession.allowsConfiguredSmartShiftWrite(for: access))
        }
        let fields = logitechSession.smartShiftManagedFields
        guard let restored = LogitechSmartShiftRestoreOperation.perform(
            change: LogitechSmartShiftFields.restoreChange(fields, from: baseline),
            shouldContinue: shouldContinue,
            readCurrentStatus: {
                access.feature.status(deadline: deadline, until: featureIOShouldContinue)
            },
            write: {
                _ = access.feature.apply($0, deadline: deadline, until: writeIsAdmitted)
            }
        ) else {
            return false
        }

        let commit = logitechSession.completeSmartShiftRestore(restored, fields: fields, for: access)
        guard case let .committed(handle) = commit else {
            return false
        }
        if let handle {
            logitechHardwareBaselineStore?.consumeSmartShiftBaseline(handle)
        }
        return true
    }

    @discardableResult
    private func seedStoredSmartShiftBaseline(receiverSlot: UInt8?) -> Bool {
        guard let lease = logitechSession.smartShiftTargetLease(
                  receiverSlot: receiverSlot,
                  stableTargetKey: { [weak self] route, slot in
                      self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
                  }
              ),
              let target = lease.stableTargetKey,
              let claim = logitechHardwareBaselineStore?.smartShiftBaseline(for: target) else {
            return false
        }
        _ = logitechSession.seedInitialSmartShiftState(claim, for: lease)
        return true
    }

    private func recordSmartShiftBaseline(
        _ status: SmartShift.Status,
        for access: LogitechDeviceSession.FeatureAccess<SmartShift>
    ) {
        _ = logitechSession.recordInitialSmartShiftState(status, for: access)
        // Discovery may enrich serial metadata while the HID read is in
        // flight, so promotion always uses a freshly validated lease.
        promoteSmartShiftBaselineIfPossible()
    }

    private func recordSmartShiftManagedFields(
        _ fields: LogitechSmartShiftFields,
        for access: LogitechDeviceSession.FeatureAccess<SmartShift>
    ) {
        let result = logitechSession.addSmartShiftManagedFields(fields, for: access)
        if let handle = result.baselineHandle {
            logitechHardwareBaselineStore?.addSmartShiftManagedFields(fields, to: handle)
        }
    }

    func promoteSmartShiftBaselineIfPossible() {
        guard let store = logitechHardwareBaselineStore,
              let lease = logitechSession.smartShiftTargetLease(
                  receiverSlot: nil,
                  stableTargetKey: { [weak self] route, slot in
                      self?.logitechHardwareTargetKey(for: route, receiverSlot: slot)
                  }
              ),
              let promotion = logitechSession.smartShiftBaselinePromotion(for: lease)
        else {
            return
        }

        let claim = store.captureSmartShiftBaseline(
            promotion.status,
            managedFields: promotion.managedFields,
            for: promotion.target
        )
        _ = logitechSession.attachSmartShiftBaseline(claim, to: promotion)
    }
}
