// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Defaults
import Foundation
import HIDPP
import ObservationToken
import os.log
import PointerKit

/// Keep HID++ cancellation at the app boundary so PointerKit remains a
/// transport-agnostic package. This lets an in-flight direct-device request
/// yield before lifecycle teardown performs its main-run-loop restore.
extension PointerDevice: HIDPPCancellableDeviceIO {}

enum PointerLinearScalingRestoreOperation {
    static func perform(
        baseline: Int?,
        write: (Int) -> Void
    ) {
        guard let baseline else {
            return
        }
        write(baseline)
    }
}

class Device {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!, category: "Device"
    )
    static let logitechOrdinaryReadTimeout: TimeInterval = 1

    static let fallbackPointerAcceleration = 0.6875
    static let fallbackPointerResolution = 400.0
    static let fallbackPointerSpeed = pointerSpeed(
        fromPointerResolution: fallbackPointerResolution
    )

    private static var nextID: Int32 = 0

    private(set) lazy var id: Int32 = OSAtomicIncrement32(&Self.nextID)

    var name: String
    var productName: String?
    var vendorID: Int?
    var productID: Int?
    var serialNumber: String?
    var buttonCount: Int?
    var batteryLevel: Int?
    private let categoryValue: Category

    private weak var manager: DeviceManager?
    private var inputReportHandlers: [InputReportHandler] = []
    private var logitechReprogrammableControlsMonitor: LogitechReprogrammableControlsMonitor?
    lazy var logitechSession = LogitechDeviceSession(deviceID: id)

    func logitechAdjustableDPI(
        for token: CancellationToken,
        deadline: Date? = nil,
        loadsSupportedDPI: Bool = true,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechDeviceSession.FeatureAccess<AdjustableDPI>? {
        logitechAdjustableDPI(
            expectedToken: token,
            requestDeadline: deadline,
            loadsSupportedDPI: loadsSupportedDPI,
            operationShouldContinue: operationShouldContinue
        )
    }

    func logitechAdjustableDPI(
        expectedToken: CancellationToken?,
        requestDeadline: Date? = nil,
        loadsSupportedDPI: Bool = true,
        operationShouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechDeviceSession.FeatureAccess<AdjustableDPI>? {
        logitechSession.adjustableDPI(expectedToken: expectedToken) { [weak self] route, token in
            guard let self else {
                return nil
            }

            let transportShouldContinue = { [weak self] in
                token.shouldContinue
                    && self?.isRemoved == false
            }
            guard let target = LogitechHIDPPFeatureTargetResolver.resolve(
                .adjustableDPI,
                for: device,
                receiverSlot: route?.slot ?? logitechSession.dpiReceiverSlotSnapshot,
                requestDeadline: requestDeadline,
                requestShouldContinue: operationShouldContinue,
                shouldContinue: transportShouldContinue
            ) else {
                return nil
            }
            let feature: AdjustableDPI
            if loadsSupportedDPI {
                guard let completeFeature = AdjustableDPI(
                    transport: target.transport,
                    featureIndex: target.featureIndex,
                    deadline: requestDeadline,
                    until: operationShouldContinue
                ) else {
                    return nil
                }
                feature = completeFeature
            } else {
                feature = AdjustableDPI(
                    transport: target.transport,
                    featureIndex: target.featureIndex,
                    supportedDPI: []
                )
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
    }

    func logitechHiResWheel(
        for token: CancellationToken,
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechDeviceSession.FeatureAccess<HiResWheel>? {
        logitechHiResWheel(
            expectedToken: token,
            requestDeadline: deadline,
            operationShouldContinue: operationShouldContinue
        )
    }

    func logitechHiResWheel(
        expectedToken: CancellationToken?,
        requestDeadline: Date? = nil,
        operationShouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechDeviceSession.FeatureAccess<HiResWheel>? {
        logitechSession.hiResWheel(expectedToken: expectedToken) { [weak self] route, token in
            guard let self else {
                return nil
            }

            let transportShouldContinue = { [weak self] in
                token.shouldContinue
                    && self?.isRemoved == false
            }
            guard let target = LogitechHIDPPFeatureTargetResolver.resolve(
                .hiresWheel,
                for: device,
                receiverSlot: route?.slot ?? logitechSession.hiResWheelReceiverSlotSnapshot,
                requestDeadline: requestDeadline,
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

    private var logitechControlsMonitorSubscriptions = Set<AnyCancellable>()
    private let device: PointerDevice

    var pointerDevice: PointerDevice {
        device
    }

    private var removed = false
    private let removalLock = NSLock()

    private var verbosedLoggingOn = Defaults[.verbosedLoggingOn]

    private let initialPointerResolution: Double
    private let initialUseLinearScalingMouseAcceleration: Int?
    lazy var logitechSettingsReconciler = LogitechDeviceSettingsReconciler(device: self)

    var logitechReceiverRouteSnapshot: LogitechReceiverRoute? {
        logitechSession.discoverySnapshot?.route
    }

    var logitechReceiverDiscoverySnapshot: LogitechReceiverDiscovery? {
        logitechSession.discoverySnapshot
    }

    func logitechHardwareTargetKey(receiverSlot: UInt8? = nil) -> LogitechHardwareTargetKey? {
        logitechHardwareTargetKey(for: logitechReceiverRouteSnapshot, receiverSlot: receiverSlot)
    }

    func logitechHardwareTargetKey(
        for route: LogitechReceiverRoute?,
        receiverSlot: UInt8? = nil
    ) -> LogitechHardwareTargetKey? {
        if let route {
            guard receiverSlot == nil || receiverSlot == route.slot else {
                return nil
            }
            return .receiver(
                vendorID: vendorID,
                receiverLocationID: pointerDevice.locationID,
                identity: route.identity
            )
        }

        guard !LogitechReceiverRouteResolver.requiresDiscovery(for: pointerDevice) else {
            return nil
        }
        if let receiverSlot {
            // On-demand legacy routing supplies a slot but no stable logical
            // identity. Never transfer a process baseline by slot alone.
            _ = receiverSlot
            return nil
        }
        return .direct(
            transport: pointerDevice.transport,
            locationID: pointerDevice.locationID,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            name: productName ?? name
        )
    }

    var logitechHardwareBaselineStore: LogitechHardwareBaselineStore? {
        manager?.logitechHardwareBaselineStore
    }

    @discardableResult
    func updateLogitechReceiverDiscovery(
        _ discovery: LogitechReceiverDiscovery?
    ) -> LogitechDeviceSession.DiscoveryUpdate {
        let update = logitechSession.updateDiscovery(discovery)
        promoteSensorDPIBaselineIfPossible()
        promoteHiResWheelBaselineIfPossible()
        if update.hardwareTargetChanged {
            logitechReprogrammableControlsMonitor?.invalidateTarget()
        }
        if !update.hardwareTargetChanged,
           update.candidateAvailabilityChanged,
           !update.hasCandidates {
            updateLogitechControlsMonitorRunning()
        }
        return update
    }

    var isRemoved: Bool {
        removalLock.withLock { removed }
    }

    private var inputObservationToken: ObservationToken?
    private var reportObservationToken: ObservationToken?

    private var lastButtonStates: UInt8 = 0

    var category: Category {
        categoryValue
    }

    init(_ manager: DeviceManager, _ device: PointerDevice) {
        self.manager = manager
        self.device = device

        vendorID = device.vendorID
        productID = device.productID
        serialNumber = device.serialNumber
        buttonCount = device.buttonCount

        let rawProductName = device.product
        let rawName = rawProductName ?? device.name
        name = rawName
        productName = rawProductName
        batteryLevel = nil
        categoryValue = Self.detectCategory(for: device)

        initialPointerResolution =
            device.pointerResolution ?? Self.fallbackPointerResolution
        initialUseLinearScalingMouseAcceleration = device.useLinearScalingMouseAcceleration

        // TODO: More elegant way?
        inputObservationToken = device.observeInput { [weak self] in
            self?.inputValueCallback($0, $1)
        }

        // Some bluetooth devices, such as Mi Dual Mode Wireless Mouse Silent Edition, report only
        // 3 buttons in the HID report descriptor. As a result, macOS does not recognize side button
        // clicks from these devices.
        //
        // To work around this issue, we subscribe to the input reports and monitor the side button
        // states. When the side buttons are clicked, we simulate those events.
        if let vendorID, let productID {
            let handlers = InputReportHandlerRegistry.handlers(for: vendorID, productID: productID)
            let needsObservation = handlers.contains { $0.alwaysNeedsReportObservation() } || buttonCount == 3
            if needsObservation, !handlers.isEmpty {
                inputReportHandlers = handlers
                reportObservationToken = device.observeReport { [weak self] in
                    self?.inputReportCallback($0, $1)
                }
            }
        }

        if LogitechReprogrammableControlsMonitor.supports(device: self) {
            let monitor = LogitechReprogrammableControlsMonitor(device: self)
            logitechReprogrammableControlsMonitor = monitor
            observeLogitechControlsMonitorDemand()
        }

        os_log(
            "Device initialized: %{public}@: HIDPointerResolution=%{public}f, HIDPointerAccelerationType=%{public}@, battery=%{public}@",
            log: Self.log,
            type: .info,
            String(describing: device),
            initialPointerResolution,
            device.pointerAccelerationType ?? "(unknown)",
            batteryLevel.map(formattedPercent) ?? "(unknown)"
        )

        Defaults.observe(.verbosedLoggingOn) { [weak self] change in
            guard let self else {
                return
            }

            verbosedLoggingOn = change.newValue
        }
        .tieToLifetime(of: self)
    }

    func markRemoved() {
        releaseSyntheticInputReportButtons()
        removalLock.withLock { removed = true }
        logitechSession.cancelAll()

        inputObservationToken = nil
        reportObservationToken = nil
        // The PointerDevice has already been invalidated by this point. Any
        // reporting cleanup must have completed through DeviceManager's async
        // stop path; do not re-enable teardown I/O during sleep or removal.
        logitechReprogrammableControlsMonitor?.abandon()
        logitechReprogrammableControlsMonitor = nil
        logitechControlsMonitorSubscriptions.removeAll()
    }

    func markActive(reason: String) {
        guard !isRemoved else {
            return
        }

        manager?.markDeviceActive(self, reason: reason)
        BatteryDeviceMonitor.shared.refreshDirectLogitechBluetoothBatteryIfNeeded(for: self)
    }

    var hasLogitechControlsMonitor: Bool {
        logitechReprogrammableControlsMonitor != nil
    }

    private var allowsDeviceWork: Bool {
        manager?.allowsDeviceWork == true
    }

    /// Stops control monitoring and best-effort restores reporting before the
    /// app's event pipeline is suspended for system sleep.
    func stopLogitechControlsMonitoringForSleep(
        authorization: CancellationToken,
        deadline: Date,
        completion: @escaping () -> Void
    ) {
        logitechControlsMonitorSubscriptions.removeAll()
        guard let logitechReprogrammableControlsMonitor else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        logitechReprogrammableControlsMonitor.stopForSleep(
            authorization: authorization,
            deadline: deadline,
            completion: completion
        )
    }

    /// Reconnects the device-level demand observers after a sleep stop. A fast
    /// wake may arrive while the reporting restore worker is still draining;
    /// the monitor coalesces that wake and reconciles demand once its cleanup
    /// barrier has released.
    func resumeLogitechControlsAfterSleep() {
        guard !isRemoved,
              allowsDeviceWork,
              let logitechReprogrammableControlsMonitor
        else {
            return
        }

        observeLogitechControlsMonitorDemand()
        logitechReprogrammableControlsMonitor.resumeAfterSleep { [weak self] in
            self?.updateLogitechControlsMonitorRunning()
        }
    }

    /// Final device teardown must not attempt HID++ I/O through an invalidated
    /// transport.
    func abandonLogitechControlsMonitoring() {
        logitechControlsMonitorSubscriptions.removeAll()
        logitechReprogrammableControlsMonitor?.abandon()
    }

    func releaseSyntheticInputReportButtons() {
        guard lastButtonStates != 0 else {
            return
        }

        let context = InputReportContext(report: Data(), lastButtonStates: lastButtonStates)
        inputReportHandlers.forEach { $0.releasePressedButtons(context) }
        lastButtonStates = 0
    }

    /// Restores a persisted Logitech controls baseline even when normal
    /// mapping demand no longer keeps the monitor running.
    func restorePendingLogitechControlsForTeardown(
        authorization: CancellationToken,
        deadline: Date,
        completion: @escaping () -> Void
    ) {
        guard let logitechReprogrammableControlsMonitor else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        logitechReprogrammableControlsMonitor.restorePendingForTeardown(
            authorization: authorization,
            deadline: deadline,
            completion: completion
        )
    }

    /// Restores DPI and Hi-Res Wheel on the existing Logitech session queue.
    /// Normal apply/retry work is frozen first; completion never depends on a
    /// main-thread HID wait and is safe to race with the outer hard deadline.
    func restoreLogitechSettingsForTeardown(
        deadline: Date,
        until operationShouldContinue: @escaping () -> Bool,
        completion: @escaping (_ restored: Bool) -> Void
    ) {
        let deliver: (Bool) -> Void = { restored in
            DispatchQueue.main.async {
                completion(restored)
            }
        }

        logitechSession.runTerminalHardwareRestore { [weak self] dpiToken, wheelToken, ownsTerminalRestore in
            guard let self else {
                deliver(false)
                return
            }

            let restored = LogitechTerminalHardwareRestoreRetry.perform(
                operations: [
                    .init(
                        shouldContinue: {
                            dpiToken.shouldContinue
                                && operationShouldContinue()
                                && ownsTerminalRestore()
                        },
                        attempt: { attempt in
                            self.restoreSensorDPIForTeardown(
                                expectedToken: dpiToken,
                                attempt: attempt
                            )
                        }
                    ),
                    .init(
                        shouldContinue: {
                            wheelToken.shouldContinue
                                && operationShouldContinue()
                                && ownsTerminalRestore()
                        },
                        attempt: { attempt in
                            self.restoreHighResolutionWheelForTeardown(
                                expectedToken: wheelToken,
                                attempt: attempt
                            )
                        }
                    )
                ],
                deadline: deadline,
                wait: Thread.sleep(forTimeInterval:)
            )
            deliver(restored)
        } onCancelled: {
            deliver(false)
        }
    }

    /// Closes every normal Logitech writer before receiver readiness or target
    /// validation begins. The monitor/session objects keep their baselines and
    /// can later perform the terminal restore through the verified route.
    func freezeLogitechForTerminalTeardown() {
        abandonLogitechControlsMonitoring()
        logitechSession.freezeTerminalHardwareMutations()
    }

    /// Revokes every outstanding Logitech teardown owner. Late callbacks are
    /// harmless because the manager's bounded request is already one-shot.
    func cancelLogitechTeardown() {
        abandonLogitechControlsMonitoring()
        prepareSensorDPIForReconnect()
        prepareHighResolutionWheelForReconnect()
    }

    func requestLogitechControlsForcedReconfiguration() {
        logitechSession.perform { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.isRemoved, self.allowsDeviceWork else {
                    return
                }

                self.updateLogitechControlsMonitorRunning()
                self.logitechReprogrammableControlsMonitor?.requestForcedReconfiguration()
            }
        }
    }

    func prepareLogitechControlsRecording() {
        guard allowsDeviceWork,
              logitechSession.allowsOrdinaryHardwareIO,
              let logitechReprogrammableControlsMonitor
        else {
            return
        }

        logitechReprogrammableControlsMonitor.enable()
        logitechReprogrammableControlsMonitor.requestReconfiguration()
    }

    private func observeLogitechControlsMonitorDemand() {
        guard logitechControlsMonitorSubscriptions.isEmpty else {
            return
        }

        ConfigurationState.shared
            .$configuration
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLogitechControlsMonitorRunning()
            }
            .store(in: &logitechControlsMonitorSubscriptions)

        SettingsState.shared
            .$buttonMappingRecordingSession
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLogitechControlsMonitorRunning()
            }
            .store(in: &logitechControlsMonitorSubscriptions)
    }

    private func updateLogitechControlsMonitorRunning() {
        guard !isRemoved,
              allowsDeviceWork,
              logitechSession.allowsOrdinaryHardwareIO else {
            return
        }

        guard let logitechReprogrammableControlsMonitor else {
            return
        }

        let receiverDiscovery = logitechReceiverDiscoverySnapshot
        let waitingForReceiverDiscovery = LogitechReceiverRouteResolver.requiresDiscovery(for: pointerDevice)
            && (receiverDiscovery?.identities.isEmpty != false)
        let needsRestoreWorker = logitechReprogrammableControlsMonitor.needsRestoreWorkerForCurrentTarget()
        if LogitechReprogrammableControlsMonitor.isNeeded(for: self) || needsRestoreWorker,
           !waitingForReceiverDiscovery {
            logitechReprogrammableControlsMonitor.enable()
        } else {
            logitechReprogrammableControlsMonitor.disable()
        }
    }
}

extension Device {
    enum Category {
        case mouse, trackpad
    }

    private static let appleVendorIDs = Set([0x004C, 0x05AC])
    private static let appleMagicMouseProductIDs = Set([0x0269, 0x030D])
    private static let appleMagicTrackpadProductIDs = Set([0x0265, 0x030E])
    private static let appleBuiltInTrackpadProductIDs = Set([0x0273, 0x0276, 0x0278, 0x0340])

    private static func detectCategory(for device: PointerDevice) -> Category {
        if let vendorID = device.vendorID,
           let productID = device.productID,
           isAppleMagicMouse(vendorID: vendorID, productID: productID) {
            return .mouse
        }

        if device.confirmsTo(kHIDPage_Digitizer, kHIDUsage_Dig_TouchPad) {
            return .trackpad
        }

        return .mouse
    }

    private static func isAppleMagicMouse(vendorID: Int, productID: Int) -> Bool {
        appleVendorIDs.contains(vendorID)
            && appleMagicMouseProductIDs.contains(productID)
    }

    private static func isAppleMagicTrackpad(vendorID: Int, productID: Int) -> Bool {
        appleVendorIDs.contains(vendorID)
            && appleMagicTrackpadProductIDs.contains(productID)
    }

    private static func isAppleBuiltInTrackpad(vendorID: Int, productID: Int) -> Bool {
        vendorID == 0x05AC
            && appleBuiltInTrackpadProductIDs.contains(productID)
    }

    var showsPointerSpeedLimitationNotice: Bool {
        guard let vendorID, let productID else {
            return false
        }

        return Self.isAppleMagicMouse(vendorID: vendorID, productID: productID)
            || Self.isAppleMagicTrackpad(vendorID: vendorID, productID: productID)
            || Self.isAppleBuiltInTrackpad(vendorID: vendorID, productID: productID)
    }

    /**
     This feature was introduced in macOS Sonoma. In the earlier versions of
     macOS, this value would be nil.
     */
    var disablePointerAcceleration: Bool? {
        get {
            device.useLinearScalingMouseAcceleration.map { $0 != 0 }
        }
        set {
            guard device.useLinearScalingMouseAcceleration != nil, let newValue else {
                return
            }
            device.useLinearScalingMouseAcceleration = newValue ? 1 : 0
        }
    }

    var pointerAcceleration: Double {
        get {
            device.pointerAcceleration ?? Self.fallbackPointerAcceleration
        }
        set {
            os_log(
                "Update pointer acceleration for device: %{public}@: %{public}f",
                log: Self.log,
                type: .info,
                String(describing: self),
                newValue
            )
            device.pointerAcceleration = newValue
        }
    }

    private static let pointerSpeedRange = 1.0 / 1200 ... 1.0 / 40

    static func pointerSpeed(fromPointerResolution pointerResolution: Double)
        -> Double {
        (1 / pointerResolution).normalized(from: pointerSpeedRange)
    }

    static func pointerResolution(fromPointerSpeed pointerSpeed: Double)
        -> Double {
        1 / (pointerSpeed.normalized(to: pointerSpeedRange))
    }

    var pointerSpeed: Double {
        get {
            device.pointerResolution.map {
                Self.pointerSpeed(fromPointerResolution: $0)
            }
                ?? Self
                .fallbackPointerSpeed
        }
        set {
            os_log(
                "Update pointer speed for device: %{public}@: %{public}f",
                log: Self.log,
                type: .info,
                String(describing: self),
                newValue
            )
            device.pointerResolution = Self.pointerResolution(fromPointerSpeed: newValue)
        }
    }

    func restorePointerAcceleration() {
        let systemPointerAcceleration = (DeviceManager.shared
            .getSystemProperty(forKey: device.pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey) as IOFixed?
        )
        .map { Double($0) / 65_536 } ?? Self.fallbackPointerAcceleration

        os_log(
            "Restore pointer acceleration for device: %{public}@: %{public}f",
            log: Self.log,
            type: .info,
            String(describing: device),
            systemPointerAcceleration
        )

        pointerAcceleration = systemPointerAcceleration
    }

    func restorePointerSpeed() {
        os_log(
            "Restore pointer speed for device: %{public}@: %{public}f",
            log: Self.log,
            type: .info,
            String(describing: device),
            Self.pointerSpeed(fromPointerResolution: initialPointerResolution)
        )

        device.pointerResolution = initialPointerResolution
    }

    /// Restore only software pointer properties. UI-level pointer-speed reset
    /// must not cancel hardware work that remains configured for the device.
    func restorePointerAccelerationAndPointerSpeed() {
        restorePointerSpeed()
        restorePointerAcceleration()
    }

    private func restoreUseLinearScalingMouseAcceleration() {
        PointerLinearScalingRestoreOperation.perform(
            baseline: initialUseLinearScalingMouseAcceleration
        ) { baseline in
            device.useLinearScalingMouseAcceleration = baseline
        }
    }

    /// Clears lifecycle-scoped Logitech access after the asynchronous hardware
    /// barrier, then restores the software pointer properties. No HID++ I/O is
    /// performed from this main-thread method.
    func finishLifecycleTeardown() {
        prepareSensorDPIForReconnect()
        prepareHighResolutionWheelForReconnect()
        restorePointerAccelerationAndPointerSpeed()
        restoreUseLinearScalingMouseAcceleration()
    }

    private func inputValueCallback(
        _ device: PointerDevice, _ value: IOHIDValue
    ) {
        if verbosedLoggingOn {
            os_log(
                "Received input value from: %{public}@: %{public}@",
                log: Self.log,
                type: .info,
                String(describing: device),
                String(describing: value)
            )
        }

        guard let manager else {
            os_log("manager is nil", log: Self.log, type: .error)
            return
        }

        guard manager.lastActiveDeviceId != id else {
            return
        }

        let element = value.element

        let usagePage = element.usagePage
        let usage = element.usage

        switch Int(usagePage) {
        case kHIDPage_GenericDesktop:
            switch Int(usage) {
            case kHIDUsage_GD_X, kHIDUsage_GD_Y, kHIDUsage_GD_Z:
                guard IOHIDValueGetIntegerValue(value) != 0 else {
                    return
                }
            default:
                return
            }
        case kHIDPage_Button:
            break
        default:
            return
        }

        manager.markDeviceActive(
            self,
            reason: "Received input value: usagePage=0x\(String(format: "%02X", usagePage)), usage=0x\(String(format: "%02X", usage))"
        )
    }

    private func inputReportCallback(_ device: PointerDevice, _ report: Data) {
        guard allowsDeviceWork else {
            return
        }

        if verbosedLoggingOn {
            let reportHex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
            os_log(
                "Received input report from: %{public}@: %{public}@",
                log: Self.log,
                type: .info,
                String(describing: device),
                String(describing: reportHex)
            )
        }

        let context = InputReportContext(report: report, lastButtonStates: lastButtonStates)
        let chain = inputReportHandlers.reversed().reduce({ (_: InputReportContext) in }) { next, handler in
            { context in handler.handleReport(context, next: next) }
        }
        chain(context)
        lastButtonStates = context.lastButtonStates
    }
}

extension Device: Hashable {
    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension Device: CustomStringConvertible {
    var description: String {
        let vendorIDString = vendorID.map { String(format: "0x%04X", $0) } ?? "(nil)"
        let productIDString = productID.map { String(format: "0x%04X", $0) } ?? "(nil)"
        return String(format: "%@ (VID=%@, PID=%@)", name, vendorIDString, productIDString)
    }
}
