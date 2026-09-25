// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import PublishedObject
import SwiftUI

class PointerSettingsState: ObservableObject {
    static let shared: PointerSettingsState = .init()

    /// How pointer movement is converted to scrolling.
    ///
    /// The stored configuration keeps its existing shape — `redirectsToScroll`
    /// plus an optional `redirectsToScrollTrigger` — so this is a reading of
    /// those two fields rather than a third one:
    ///
    /// | mode | `redirectsToScroll` | `redirectsToScrollTrigger` |
    /// | --- | --- | --- |
    /// | `off` | `false` | ignored |
    /// | `whileHoldingTrigger` | `true` | set |
    /// | `always` | `true` | unset |
    enum RedirectsToScrollMode: Hashable, CaseIterable, Identifiable {
        case off
        case whileHoldingTrigger
        case always

        var id: Self {
            self
        }
    }

    @PublishedObject private var schemeState = SchemeState.shared
    private let deviceState = DeviceState.shared
    private var subscriptions = Set<AnyCancellable>()

    /// Held while the user has picked a mode the configuration cannot represent
    /// yet: `whileHoldingTrigger` before a trigger has been recorded, and
    /// `always` while it waits to be confirmed. Cleared once the configuration
    /// catches up, after which the mode is read back from the scheme.
    @Published private var pendingRedirectsToScrollMode: RedirectsToScrollMode?

    /// Set while the "Always" confirmation is on screen.
    @Published var redirectsToScrollAlwaysConfirmationPresented = false

    /// Counts down while "Always" is applied but not yet kept. `nil` when no
    /// revert is pending.
    @Published private(set) var redirectsToScrollAlwaysSecondsUntilRevert: Int?

    private var redirectsToScrollAlwaysRevertTimer: Timer?

    /// What the trigger recorder shows while it is recording.
    ///
    /// The recorder clears its mapping when recording starts, but the stored
    /// trigger has to stay in place until a new one is recorded, or movement
    /// would be converted unconditionally in the meantime. The cleared (or
    /// partially recorded) mapping is kept here instead, so the recorder shows
    /// "Recording" rather than the old trigger. `nil` when not recording.
    @Published private var redirectsToScrollTriggerRecordingMapping: Scheme.Buttons.Mapping?

    /// What to put back if "Always" is not kept in time.
    private var redirectsToScrollStateBeforeAlways: RedirectsToScrollState?

    /// Long enough to notice the pointer has been taken over and reach for the
    /// keyboard, short enough that an unattended Mac frees itself quickly.
    static let redirectsToScrollAlwaysRevertSeconds = 10

    private struct RedirectsToScrollState {
        var redirectsToScroll: Bool
        var trigger: Scheme.Trigger?
    }

    @Published private(set) var pointerHardwareDPIInfo: Device.HardwareDPIInfo?
    @Published private(set) var pointerHardwareDPIInfoRefreshing = false
    @Published private(set) var pointerHardwareDPITargetDPI = 400
    @Published private(set) var pointerHardwareDPIApplying = false
    @Published private(set) var pointerHardwareDPIStatusMessage: String?
    private var pointerHardwareDPITargetDPIEdited = false
    private var pointerHardwareDPIApplyWorkItem: DispatchWorkItem?
    private var pointerHardwareDPIRefreshPending = false
    private var receiverIdentitiesByLocation = [Int: [ReceiverLogicalDeviceIdentity]]()

    private static let pointerHardwareDPIApplyDebounceInterval: TimeInterval = 0.25

    private init() {
        deviceState.$currentDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetPointerHardwareDPIState()
                // A pending mode or revert belongs to the device it was started
                // on, and the countdown would otherwise put that device's
                // settings back while a different one is selected.
                self?.resetRedirectsToScrollModeState()
                self?.refreshPointerHardwareDPIInfo()
            }
            .store(in: &subscriptions)

        // Recording can end without a new trigger (clicking the recorder
        // again, or switching away). Drop the in-progress mapping so the
        // recorder goes back to showing the stored trigger.
        SettingsState.shared
            .$buttonMappingRecordingSession
            .filter { $0 == nil }
            .sink { [weak self] _ in
                self?.redirectsToScrollTriggerRecordingMapping = nil
            }
            .store(in: &subscriptions)

        DeviceManager.shared
            .$receiverPairedDeviceIdentities
            .sink { [weak self] identitiesByLocation in
                guard let self,
                      let device = self.currentDevice,
                      LogitechReceiverRouteResolver.requiresDiscovery(for: device.pointerDevice),
                      let locationID = device.pointerDevice.locationID
                else {
                    return
                }

                let identities = identitiesByLocation[locationID] ?? []
                guard self.receiverIdentitiesByLocation[locationID] != identities else {
                    return
                }
                self.receiverIdentitiesByLocation[locationID] = identities

                // @Published emits before DeviceManager updates the device's
                // route. Defer to the next main-queue turn so the read sees
                // either the new route or its explicit unavailable state.
                DispatchQueue.main.async { [weak self, weak device] in
                    guard let self, self.currentDevice === device else {
                        return
                    }

                    self.refreshPointerHardwareDPIInfo()
                }
            }
            .store(in: &subscriptions)
    }

    var scheme: Scheme {
        get { schemeState.scheme }
        set { schemeState.scheme = newValue }
    }

    var mergedScheme: Scheme {
        schemeState.mergedScheme
    }

    var pointerHardwareDPIBusy: Bool {
        pointerHardwareDPIInfoRefreshing || pointerHardwareDPIApplying
    }

    var showsPointerHardwareDPIControl: Bool {
        pointerHardwareDPIInfo?.supportsAdjustableDPI == true
    }

    private var currentDevice: Device? {
        deviceState.currentDeviceRef?.value
    }
}

extension PointerSettingsState {
    var pointerDisableAcceleration: Bool {
        get {
            mergedScheme.pointer.disableAcceleration ?? false
        }
        set {
            scheme.pointer.disableAcceleration = newValue
        }
    }

    var pointerRedirectsToScroll: Bool {
        mergedScheme.pointer.redirectsToScroll ?? false
    }

    /// The mode shown in the picker.
    ///
    /// Reads back from the scheme unless a pending selection is outstanding,
    /// so a mode that has not been applied yet still appears selected.
    var pointerRedirectsToScrollMode: RedirectsToScrollMode {
        get { pendingRedirectsToScrollMode ?? storedRedirectsToScrollMode }
        set { selectRedirectsToScrollMode(newValue) }
    }

    private var storedRedirectsToScrollMode: RedirectsToScrollMode {
        Self.redirectsToScrollMode(
            redirectsToScroll: pointerRedirectsToScroll,
            trigger: pointerRedirectsToScrollTrigger
        )
    }

    /// Reads the mode out of the two stored fields.
    static func redirectsToScrollMode(
        redirectsToScroll: Bool,
        trigger: Scheme.Trigger?
    ) -> RedirectsToScrollMode {
        guard redirectsToScroll else {
            return .off
        }

        return trigger == nil ? .always : .whileHoldingTrigger
    }

    private func selectRedirectsToScrollMode(_ mode: RedirectsToScrollMode) {
        guard mode != pointerRedirectsToScrollMode else {
            return
        }

        // Picking any mode abandons a revert that is still counting down: the
        // user is clearly still in control of an input device.
        cancelRedirectsToScrollAlwaysRevert()

        switch mode {
        case .off:
            pendingRedirectsToScrollMode = nil
            applyRedirectsToScroll(false, trigger: pointerRedirectsToScrollTrigger)

        case .whileHoldingTrigger:
            guard let trigger = pointerRedirectsToScrollTrigger else {
                // Turning redirecting on now would convert every movement until
                // a trigger is recorded — exactly the trap this mode exists to
                // avoid. Show the recorder and leave the pointer alone.
                pendingRedirectsToScrollMode = .whileHoldingTrigger
                applyRedirectsToScroll(false, trigger: nil)
                return
            }

            pendingRedirectsToScrollMode = nil
            applyRedirectsToScroll(true, trigger: trigger)

        case .always:
            // This takes the pointer away from the selected device, so it is
            // confirmed first and then reverted unless it is confirmed again.
            redirectsToScrollStateBeforeAlways = RedirectsToScrollState(
                redirectsToScroll: pointerRedirectsToScroll,
                trigger: pointerRedirectsToScrollTrigger
            )
            pendingRedirectsToScrollMode = .always
            redirectsToScrollAlwaysConfirmationPresented = true
        }
    }

    /// Applies "Always" and starts the countdown that undoes it.
    func confirmRedirectsToScrollAlways() {
        redirectsToScrollAlwaysConfirmationPresented = false
        pendingRedirectsToScrollMode = nil
        applyRedirectsToScroll(true, trigger: nil)
        startRedirectsToScrollAlwaysRevertCountdown()
    }

    /// Dismisses the confirmation without applying anything.
    func cancelRedirectsToScrollAlways() {
        redirectsToScrollAlwaysConfirmationPresented = false
        pendingRedirectsToScrollMode = nil
        redirectsToScrollStateBeforeAlways = nil
    }

    /// Keeps "Always" and stops the countdown.
    func keepRedirectsToScrollAlways() {
        cancelRedirectsToScrollAlwaysRevert()
    }

    /// Puts back whatever was configured before "Always" was applied.
    func revertRedirectsToScrollAlways() {
        guard let previous = redirectsToScrollStateBeforeAlways else {
            cancelRedirectsToScrollAlwaysRevert()
            applyRedirectsToScroll(false, trigger: pointerRedirectsToScrollTrigger)
            return
        }

        cancelRedirectsToScrollAlwaysRevert()
        applyRedirectsToScroll(previous.redirectsToScroll, trigger: previous.trigger)
    }

    private func startRedirectsToScrollAlwaysRevertCountdown() {
        redirectsToScrollAlwaysSecondsUntilRevert = Self.redirectsToScrollAlwaysRevertSeconds

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            guard let remaining = self.redirectsToScrollAlwaysSecondsUntilRevert else {
                self.cancelRedirectsToScrollAlwaysRevert()
                return
            }

            guard remaining > 1 else {
                self.revertRedirectsToScrollAlways()
                return
            }

            self.redirectsToScrollAlwaysSecondsUntilRevert = remaining - 1
        }

        // .common so the countdown keeps running while a menu or a slider is
        // being tracked, which is otherwise exactly when it would stall.
        RunLoop.main.add(timer, forMode: .common)
        redirectsToScrollAlwaysRevertTimer = timer
    }

    private func cancelRedirectsToScrollAlwaysRevert() {
        redirectsToScrollAlwaysRevertTimer?.invalidate()
        redirectsToScrollAlwaysRevertTimer = nil
        redirectsToScrollAlwaysSecondsUntilRevert = nil
        redirectsToScrollStateBeforeAlways = nil
    }

    private func resetRedirectsToScrollModeState() {
        cancelRedirectsToScrollAlwaysRevert()
        redirectsToScrollAlwaysConfirmationPresented = false
        pendingRedirectsToScrollMode = nil
        redirectsToScrollTriggerRecordingMapping = nil
    }

    /// Writes both fields in one update so the scheme never passes through a
    /// state the mode cannot describe, then restarts the tap to pick it up.
    private func applyRedirectsToScroll(_ enabled: Bool, trigger: Scheme.Trigger?) {
        var updated = scheme
        updated.pointer.redirectsToScroll = enabled
        updated.pointer.redirectsToScrollTrigger = trigger
        scheme = updated

        GlobalEventTap.shared.stop()
        GlobalEventTap.shared.start()
    }

    var pointerRedirectsToScrollTrigger: Scheme.Trigger? {
        get {
            mergedScheme.pointer.redirectsToScrollTrigger
        }
        set {
            guard let newValue else {
                // Clearing the trigger must not leave `redirectsToScroll` on,
                // or the mode would silently become "Always" and take the
                // pointer over. Fall back to waiting for a new trigger.
                pendingRedirectsToScrollMode = .whileHoldingTrigger
                applyRedirectsToScroll(false, trigger: nil)
                return
            }

            // Recording a trigger is what completes a pending
            // `whileHoldingTrigger` selection.
            let enable = pendingRedirectsToScrollMode == .whileHoldingTrigger || pointerRedirectsToScroll
            pendingRedirectsToScrollMode = nil
            applyRedirectsToScroll(enable, trigger: newValue)
        }
    }

    /// Adapts the trigger to the mapping shape used by `ButtonMappingButtonRecorder`.
    var pointerRedirectsToScrollTriggerBinding: Binding<Scheme.Buttons.Mapping> {
        Binding(
            get: { [self] in
                if let redirectsToScrollTriggerRecordingMapping {
                    return redirectsToScrollTriggerRecordingMapping
                }

                var mapping = Scheme.Buttons.Mapping()
                if case let .button(button) = pointerRedirectsToScrollTrigger?.input {
                    mapping.button = button
                }
                mapping.modifierFlags = pointerRedirectsToScrollTrigger?.modifierFlags ?? []
                return mapping
            },
            set: { [self] in
                guard let trigger = $0.effectiveTrigger else {
                    // Recording has started or is part way through. Show that
                    // in the recorder, but keep the stored trigger until a new
                    // one is recorded.
                    redirectsToScrollTriggerRecordingMapping = $0
                    return
                }

                redirectsToScrollTriggerRecordingMapping = nil
                pointerRedirectsToScrollTrigger = trigger
            }
        )
    }

    var pointerRedirectsToScrollTriggerValid: Bool {
        pointerRedirectsToScrollTrigger?.isValidRedirectsToScrollTrigger ?? true
    }

    var pointerAcceleration: Double {
        get {
            mergedScheme.pointer.acceleration?.unwrapped?.asTruncatedDouble
                ?? mergedScheme.firstMatchedDevice?.pointerAcceleration
                ?? Device.fallbackPointerAcceleration
        }
        set {
            guard abs(pointerAcceleration - newValue) >= 0.0001 else {
                return
            }

            scheme.pointer.acceleration = .value(Decimal(newValue).rounded(4))
        }
    }

    var pointerSpeed: Double {
        get {
            mergedScheme.pointer.speed?.unwrapped?.asTruncatedDouble
                ?? mergedScheme.firstMatchedDevice?.pointerSpeed
                ?? Device.fallbackPointerSpeed
        }
        set {
            guard abs(pointerSpeed - newValue) >= 0.0001 else {
                return
            }

            scheme.pointer.speed = .value(Decimal(newValue).rounded(4))
        }
    }

    var pointerAccelerationFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 4
        formatter.thousandSeparator = ""
        return formatter
    }

    var pointerSpeedFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 4
        formatter.thousandSeparator = ""
        return formatter
    }

    var pointerDPIFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.none
        formatter.allowsFloats = false
        formatter.thousandSeparator = ""
        return formatter
    }

    func refreshPointerHardwareDPIInfo() {
        guard !pointerHardwareDPIInfoRefreshing, !pointerHardwareDPIApplying else {
            pointerHardwareDPIRefreshPending = true
            return
        }

        pointerHardwareDPIInfoRefreshing = true
        pointerHardwareDPIStatusMessage = nil

        guard let device = currentDevice else {
            pointerHardwareDPIStatusMessage = "No selected device"
            pointerHardwareDPIInfoRefreshing = false
            return
        }

        device.refreshHardwareDPIInfo { [weak self] info in
            guard let self else {
                return
            }

            guard self.currentDevice === device else {
                self.pointerHardwareDPIInfoRefreshing = false
                self.resetPointerHardwareDPIState()
                self.refreshPointerHardwareDPIInfo()
                return
            }

            if let currentDPI = info.currentDPI,
               !self.pointerHardwareDPITargetDPIEdited {
                self.pointerHardwareDPITargetDPI = currentDPI
            }
            self.pointerHardwareDPIInfo = info
            self.pointerHardwareDPIStatusMessage = self.pointerHardwareDPIStatusMessage(for: info)
            self.pointerHardwareDPIInfoRefreshing = false
            self.refreshPointerHardwareDPIInfoIfNeeded()
        }
    }

    func applyPointerHardwareDPITargetDPI() {
        guard !pointerHardwareDPIInfoRefreshing, !pointerHardwareDPIApplying else {
            return
        }

        pointerHardwareDPIApplying = true
        pointerHardwareDPIStatusMessage = nil
        let requestedDPI = pointerHardwareDPITargetDPI

        guard let device = currentDevice else {
            pointerHardwareDPIStatusMessage = "No selected device"
            pointerHardwareDPIApplying = false
            return
        }

        device.applyHardwareDPI(requestedDPI) { [weak self] result in
            guard let self else {
                return
            }

            guard self.currentDevice === device else {
                self.pointerHardwareDPIApplying = false
                self.resetPointerHardwareDPIState()
                self.refreshPointerHardwareDPIInfo()
                return
            }

            guard self.pointerHardwareDPITargetDPI == requestedDPI else {
                self.pointerHardwareDPIApplying = false
                if self.pointerHardwareDPIApplyWorkItem == nil {
                    self.applyPointerHardwareDPITargetDPI()
                }
                return
            }

            if result.outcome == .cancelled {
                self.pointerHardwareDPIApplying = false
                self.pointerHardwareDPIRefreshPending = false
                self.refreshPointerHardwareDPIInfo()
                return
            }

            if !result.info.supportsAdjustableDPI {
                self.pointerHardwareDPIStatusMessage = "Unsupported device"
            } else if let targetDPI = result.targetDPI {
                self.pointerHardwareDPITargetDPI = targetDPI
                self.pointerHardwareDPITargetDPIEdited = false
                var deviceScheme = self.schemeState.deviceScheme
                deviceScheme.pointer.hardwareDPI = targetDPI
                self.schemeState.deviceScheme = deviceScheme
                self.pointerHardwareDPIStatusMessage = nil
            } else {
                if let currentDPI = Self.displayedHardwareDPI(after: result) {
                    self.pointerHardwareDPITargetDPI = currentDPI
                }
                self.pointerHardwareDPITargetDPIEdited = false
                self.pointerHardwareDPIStatusMessage = "Unable to apply DPI"
            }

            self.pointerHardwareDPIInfo = result.info
            self.pointerHardwareDPIApplying = false
            self.refreshPointerHardwareDPIInfoIfNeeded()
        }
    }

    static func displayedHardwareDPI(after result: Device.HardwareDPIApplyResult) -> Int? {
        result.targetDPI ?? result.info.currentDPI
    }

    private func resetPointerHardwareDPIState() {
        pointerHardwareDPIApplyWorkItem?.cancel()
        pointerHardwareDPIApplyWorkItem = nil
        pointerHardwareDPIInfo = nil
        pointerHardwareDPIStatusMessage = nil
        pointerHardwareDPITargetDPIEdited = false
        pointerHardwareDPIRefreshPending = false
    }

    private func refreshPointerHardwareDPIInfoIfNeeded() {
        guard pointerHardwareDPIRefreshPending else {
            return
        }

        pointerHardwareDPIRefreshPending = false
        refreshPointerHardwareDPIInfo()
    }

    func updatePointerHardwareDPITargetDPI(_ dpi: Int) {
        updatePointerHardwareDPITargetDPI(
            dpi,
            applyDelay: Self.pointerHardwareDPIApplyDebounceInterval
        )
    }

    func commitPointerHardwareDPITargetDPI(_ dpi: Int) {
        updatePointerHardwareDPITargetDPI(dpi, applyDelay: 0)
    }

    private func updatePointerHardwareDPITargetDPI(_ dpi: Int, applyDelay: TimeInterval) {
        pointerHardwareDPITargetDPI = dpi
        pointerHardwareDPITargetDPIEdited = true
        pointerHardwareDPIStatusMessage = nil

        pointerHardwareDPIApplyWorkItem?.cancel()
        guard let device = currentDevice else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.currentDevice === device else {
                return
            }

            self.pointerHardwareDPIApplyWorkItem = nil
            self.applyPointerHardwareDPITargetDPI()
        }
        pointerHardwareDPIApplyWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + applyDelay,
            execute: workItem
        )
    }

    private func pointerHardwareDPIStatusMessage(for info: Device.HardwareDPIInfo) -> String? {
        if !info.supportsAdjustableDPI {
            return "Unsupported device"
        }

        if info.currentDPI == nil {
            return "Unable to read DPI"
        }

        return nil
    }

    var showsPointerSpeedLimitationNotice: Bool {
        mergedScheme.firstMatchedDevice?.showsPointerSpeedLimitationNotice ?? false
    }

    func revertPointerSpeed() {
        let device = scheme.firstMatchedDevice

        device?.restorePointerAccelerationAndPointerSpeed()

        // This turns redirecting off, so a pending selection or countdown no
        // longer has anything to apply or put back.
        resetRedirectsToScrollModeState()

        Scheme(
            pointer: Scheme.Pointer(
                acceleration: .unset,
                speed: .unset,
                disableAcceleration: false,
                redirectsToScroll: false
            )
        )
        .merge(into: &scheme)
    }
}
