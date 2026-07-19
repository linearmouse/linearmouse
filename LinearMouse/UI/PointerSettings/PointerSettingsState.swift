// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import PublishedObject

class PointerSettingsState: ObservableObject {
    static let shared: PointerSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    private let deviceState = DeviceState.shared
    private var subscriptions = Set<AnyCancellable>()

    @Published private(set) var pointerHardwareDPIInfo: Device.HardwareDPIInfo?
    @Published private(set) var pointerHardwareDPIInfoRefreshing = false
    @Published private(set) var pointerHardwareDPITargetDPI = 400
    @Published private(set) var pointerHardwareDPIApplying = false
    @Published private(set) var pointerHardwareDPIStatusMessage: String?
    private var pointerHardwareDPITargetDPIEdited = false
    private var pointerHardwareDPIApplyWorkItem: DispatchWorkItem?

    private static let pointerHardwareDPIApplyDebounceInterval: TimeInterval = 0.25

    private init() {
        deviceState.$currentDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetPointerHardwareDPIState()
                self?.refreshPointerHardwareDPIInfo()
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
        get {
            mergedScheme.pointer.redirectsToScroll ?? false
        }
        set {
            scheme.pointer.redirectsToScroll = newValue
            GlobalEventTap.shared.stop()
            GlobalEventTap.shared.start()
        }
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
                self.pointerHardwareDPIStatusMessage = "Unable to apply DPI"
            }

            self.pointerHardwareDPIInfo = result.info
            self.pointerHardwareDPIApplying = false
        }
    }

    private func resetPointerHardwareDPIState() {
        pointerHardwareDPIApplyWorkItem?.cancel()
        pointerHardwareDPIApplyWorkItem = nil
        pointerHardwareDPIInfo = nil
        pointerHardwareDPIStatusMessage = nil
        pointerHardwareDPITargetDPIEdited = false
    }

    func updatePointerHardwareDPITargetDPI(_ dpi: Int) {
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
            deadline: .now() + Self.pointerHardwareDPIApplyDebounceInterval,
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
