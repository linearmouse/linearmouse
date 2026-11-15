// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Foundation
import HIDPP
import PublishedObject
import SwiftUI

class ScrollingSettingsState: ObservableObject {
    static let shared: ScrollingSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    private let deviceState = DeviceState.shared
    private var subscriptions = Set<AnyCancellable>()
    private var smoothedCache = Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>()

    @Published private(set) var highResolutionWheelInfo: Device.HighResolutionWheelInfo?
    @Published private(set) var highResolutionWheelInfoRefreshing = false
    private var highResolutionWheelInfoRefreshPending = false
    @Published private(set) var smartShiftInfo: Device.SmartShiftInfo?
    private var smartShiftInfoRefreshing = false
    private var smartShiftInfoRefreshPending = false
    private var receiverIdentitiesByLocation = [Int: [ReceiverLogicalDeviceIdentity]]()

    private init() {
        deviceState.$currentDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetHighResolutionWheelInfo()
                self?.refreshHighResolutionWheelInfo()
                self?.resetSmartShiftInfo()
                self?.refreshSmartShiftInfo()
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

                    self.refreshHighResolutionWheelInfo()
                    self.refreshSmartShiftInfo()
                }
            }
            .store(in: &subscriptions)

        NSWorkspace.shared
            .notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetHighResolutionWheelInfo()
                self?.refreshHighResolutionWheelInfo()
                self?.resetSmartShiftInfo()
                self?.refreshSmartShiftInfo()
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

    @Published var direction: Scheme.Scrolling.BidirectionalDirection = .vertical

    private var currentDevice: Device? {
        deviceState.currentDeviceRef?.value
    }
}

extension ScrollingSettingsState {
    var reverseScrolling: Bool {
        get { mergedScheme.scrolling.reverse[direction] ?? false }
        set { scheme.scrolling.reverse[direction] = newValue }
    }

    var showsHighResolutionWheelControl: Bool {
        highResolutionWheelInfo?.supportsHighResolutionWheel == true
    }

    var highResolutionWheel: Bool {
        get {
            schemeState.deviceScheme.logitech.highResolutionWheel
                ?? highResolutionWheelInfo?.enabled
                ?? false
        }
        set {
            var deviceScheme = schemeState.deviceScheme
            deviceScheme.logitech.highResolutionWheel = newValue
            schemeState.deviceScheme = deviceScheme

            if let currentDevice {
                DeviceManager.shared.updateLogitechDeviceSettings(for: currentDevice)
            }
        }
    }

    func refreshHighResolutionWheelInfo() {
        guard !highResolutionWheelInfoRefreshing else {
            highResolutionWheelInfoRefreshPending = true
            return
        }

        guard let device = currentDevice else {
            resetHighResolutionWheelInfo()
            return
        }

        highResolutionWheelInfoRefreshing = true
        device.refreshHighResolutionWheelInfo { [weak self] info in
            guard let self else {
                return
            }

            guard self.currentDevice === device else {
                self.highResolutionWheelInfoRefreshing = false
                self.resetHighResolutionWheelInfo()
                self.refreshHighResolutionWheelInfo()
                return
            }

            self.highResolutionWheelInfo = info
            self.highResolutionWheelInfoRefreshing = false
            self.applyConfiguredHighResolutionWheelIfNeeded(info: info, device: device)
            self.refreshHighResolutionWheelInfoIfNeeded()
        }
    }

    private func resetHighResolutionWheelInfo() {
        highResolutionWheelInfo = nil
        // Keep an in-flight read marked as such. Its completion will notice a
        // new selected device and start one coalesced read for that device;
        // clearing this here would allow stale and current reads to overlap.
        highResolutionWheelInfoRefreshPending = false
    }

    private func refreshHighResolutionWheelInfoIfNeeded() {
        guard highResolutionWheelInfoRefreshPending else {
            return
        }

        highResolutionWheelInfoRefreshPending = false
        refreshHighResolutionWheelInfo()
    }

    private func applyConfiguredHighResolutionWheelIfNeeded(info: Device.HighResolutionWheelInfo, device: Device) {
        guard info.supportsHighResolutionWheel,
              let configuredHighResolutionWheel = schemeState.deviceScheme.logitech.highResolutionWheel,
              info.enabled != configuredHighResolutionWheel else {
            return
        }

        DeviceManager.shared.updateLogitechDeviceSettings(for: device)
    }

    /// The slider's usable band, after OpenLogi's: below 8 a wheel can free
    /// spin during everyday scrolling, and a flick rarely reaches more than 50.
    /// The configuration still accepts the full 1–254 wire range.
    static let smartShiftThresholdRange = 8 ... 50
    private static let fallbackSmartShiftThreshold = 16
    private static let defaultSmartShiftTorque = 50

    var showsSmartShiftControl: Bool {
        smartShiftInfo?.supportsSmartShift == true
    }

    var supportsSmartShiftTorque: Bool {
        smartShiftInfo?.supportsTunableTorque == true
    }

    private var configuredSmartShift: Scheme.Logitech.SmartShift? {
        schemeState.deviceScheme.logitech.smartShift
    }

    var smartShiftMode: Scheme.Logitech.SmartShift.Mode {
        get {
            if let mode = configuredSmartShift?.mode {
                return mode
            }
            return smartShiftInfo?.status?.wheelMode == .freeSpin ? .freeSpin : .ratchet
        }
        set {
            updateSmartShift { $0.mode = newValue }
        }
    }

    var smartShiftAutomatic: Bool {
        get {
            switch configuredSmartShift?.autoDisengage {
            case .threshold?:
                return true
            case .never?:
                return false
            case nil:
                return smartShiftInfo?.status.map { $0.autoDisengage != SmartShift.permanentRatchet } ?? true
            }
        }
        set {
            let threshold = smartShiftThreshold
            updateSmartShift { $0.autoDisengage = newValue ? .threshold(threshold) : .never }
        }
    }

    var smartShiftThreshold: Int {
        get {
            var configured: Int?
            if case let .threshold(threshold)? = configuredSmartShift?.autoDisengage {
                configured = threshold
            }
            return Self.smartShiftSliderThreshold(
                configured: configured,
                current: smartShiftInfo?.status?.autoDisengage,
                deviceDefault: smartShiftInfo?.defaultAutoDisengage
            )
        }
        set {
            updateSmartShift { $0.autoDisengage = .threshold(newValue) }
        }
    }

    var smartShiftTorque: Int {
        get {
            configuredSmartShift?.torque
                ?? smartShiftInfo?.status?.torque.map(Int.init)
                ?? Self.defaultSmartShiftTorque
        }
        set {
            updateSmartShift { $0.torque = newValue }
        }
    }

    /// The threshold the slider shows: the configured value, else the wheel's
    /// current one, else its factory default, kept inside the slider's band.
    /// A value below the band is replaced rather than clamped, because it is a
    /// threshold the slider deliberately does not offer.
    static func smartShiftSliderThreshold(
        configured: Int?,
        current: UInt8?,
        deviceDefault: UInt8?
    ) -> Int {
        let range = smartShiftThresholdRange
        let fallback = deviceDefault.map(Int.init).flatMap { range.contains($0) ? $0 : nil }
            ?? fallbackSmartShiftThreshold
        let current = current.flatMap { $0 == SmartShift.permanentRatchet ? nil : Int($0) }
        let candidate = configured ?? current ?? fallback
        guard candidate >= range.lowerBound else {
            return fallback
        }
        return min(candidate, range.upperBound)
    }

    private func updateSmartShift(_ update: (inout Scheme.Logitech.SmartShift) -> Void) {
        var deviceScheme = schemeState.deviceScheme
        var smartShift = deviceScheme.logitech.smartShift ?? .init()
        update(&smartShift)
        deviceScheme.logitech.smartShift = smartShift
        schemeState.deviceScheme = deviceScheme

        if let currentDevice {
            DeviceManager.shared.updateLogitechDeviceSettings(for: currentDevice)
        }
    }

    func refreshSmartShiftInfo() {
        guard !smartShiftInfoRefreshing else {
            smartShiftInfoRefreshPending = true
            return
        }

        guard let device = currentDevice else {
            resetSmartShiftInfo()
            return
        }

        smartShiftInfoRefreshing = true
        device.refreshSmartShiftInfo { [weak self] info in
            guard let self else {
                return
            }

            self.smartShiftInfoRefreshing = false
            guard self.currentDevice === device else {
                self.resetSmartShiftInfo()
                self.refreshSmartShiftInfo()
                return
            }

            self.smartShiftInfo = info
            if self.smartShiftInfoRefreshPending {
                self.smartShiftInfoRefreshPending = false
                self.refreshSmartShiftInfo()
            }
        }
    }

    private func resetSmartShiftInfo() {
        smartShiftInfo = nil
        smartShiftInfoRefreshPending = false
    }

    enum ScrollingMode: String, Identifiable, CaseIterable {
        var id: Self {
            self
        }

        case accelerated = "Accelerated"
        case smoothed = "Smoothed"
        case byLines = "By Lines"
        case byPixels = "By Pixels"

        var label: LocalizedStringKey {
            switch self {
            case .accelerated:
                "Accelerated"
            case .smoothed:
                "Smoothed (Beta)"
            case .byLines:
                "By Lines"
            case .byPixels:
                "By Pixels"
            }
        }

        var sendsContinuousScrollEvents: Bool {
            switch self {
            case .smoothed, .byPixels:
                true
            case .accelerated, .byLines:
                false
            }
        }
    }

    var scrollingMode: ScrollingMode {
        get {
            if currentSmoothedConfiguration != nil {
                return .smoothed
            }

            switch mergedScheme.scrolling.distance[direction] ?? .auto {
            case .auto:
                return .accelerated
            case .line:
                return .byLines
            case .pixel:
                return .byPixels
            }
        }
        set {
            switch newValue {
            case .accelerated:
                clearSmoothedConfiguration()
                scheme.scrolling.distance[direction] = .auto
                scheme.scrolling.acceleration[direction] = 1
                scheme.scrolling.speed[direction] = 0
            case .smoothed:
                let smoothed = currentSmoothedConfiguration ?? makeDefaultSmoothedConfiguration()
                setSmoothedConfiguration(smoothed)
                scheme.scrolling.distance[direction] = .auto
                scheme.scrolling.acceleration[direction] = 1
                scheme.scrolling.speed[direction] = 0
            case .byLines:
                clearSmoothedConfiguration()
                scheme.scrolling.distance[direction] = .line(3)
                scheme.scrolling.acceleration[direction] = 1
                scheme.scrolling.speed[direction] = 0
            case .byPixels:
                clearSmoothedConfiguration()
                scheme.scrolling.distance[direction] = .pixel(36)
                scheme.scrolling.acceleration[direction] = 1
                scheme.scrolling.speed[direction] = 0
            }
        }
    }

    var scrollingAcceleration: Double {
        get { mergedScheme.scrolling.acceleration[direction]?.asTruncatedDouble ?? 1 }
        set { scheme.scrolling.acceleration[direction] = Decimal(newValue).rounded(2) }
    }

    var scrollingAccelerationFormatter: NumberFormatter {
        decimalFormatter(maxFractionDigits: 2)
    }

    var scrollingSpeed: Double {
        get { mergedScheme.scrolling.speed[direction]?.asTruncatedDouble ?? 0 }
        set { scheme.scrolling.speed[direction] = Decimal(newValue).rounded(2) }
    }

    var scrollingSpeedFormatter: NumberFormatter {
        decimalFormatter(maxFractionDigits: 2)
    }

    var scrollingDistanceInLines: Double {
        get {
            guard case let .line(lines) = mergedScheme.scrolling.distance[direction] else {
                return 3
            }
            return Double(lines)
        }
        set {
            scheme.scrolling.distance[direction] = .line(Int(newValue))
        }
    }

    var scrollingDistanceInPixels: Double {
        get {
            guard case let .pixel(pixels) = mergedScheme.scrolling.distance[direction] else {
                return 36
            }
            return pixels.asTruncatedDouble
        }
        set {
            scheme.scrolling.distance[direction] = .pixel(Decimal(newValue).rounded(1))
        }
    }

    var smoothedPreset: Scheme.Scrolling.Smoothed.Preset {
        get { currentSmoothedConfiguration?.preset ?? .defaultPreset }
        set {
            selectSmoothedPreset(newValue)
        }
    }

    var smoothedResponse: Double {
        get { currentSmoothedConfiguration?.response?.asTruncatedDouble ?? 0.68 }
        set {
            updateSmoothedConfiguration {
                $0.response = Decimal(newValue).rounded(2)
            }
        }
    }

    var smoothedResponseFormatter: NumberFormatter {
        decimalFormatter(maxFractionDigits: 2)
    }

    var smoothedSpeed: Double {
        get { currentSmoothedConfiguration?.speed?.asTruncatedDouble ?? 1.02 }
        set {
            updateSmoothedConfiguration {
                $0.speed = Decimal(newValue).rounded(2)
            }
        }
    }

    var smoothedSpeedFormatter: NumberFormatter {
        decimalFormatter(maxFractionDigits: 2)
    }

    var smoothedAcceleration: Double {
        get { currentSmoothedConfiguration?.acceleration?.asTruncatedDouble ?? 1.10 }
        set {
            updateSmoothedConfiguration {
                $0.acceleration = Decimal(newValue).rounded(2)
            }
        }
    }

    var smoothedAccelerationFormatter: NumberFormatter {
        decimalFormatter(maxFractionDigits: 2)
    }

    var smoothedInertia: Double {
        get { currentSmoothedConfiguration?.inertia?.asTruncatedDouble ?? 0.74 }
        set {
            updateSmoothedConfiguration {
                $0.inertia = Decimal(newValue).rounded(2)
            }
        }
    }

    var smoothedInertiaFormatter: NumberFormatter {
        decimalFormatter(maxFractionDigits: 2)
    }

    var smoothedBouncing: Bool {
        get { currentSmoothedConfiguration?.allowsBouncing ?? true }
        set {
            updateSmoothedConfiguration {
                $0.bouncing = newValue
            }
        }
    }

    var scrollingDisabled: Bool {
        switch scrollingMode {
        case .accelerated:
            return scrollingAcceleration == 0 && scrollingSpeed == 0
        case .smoothed:
            return smoothedResponse == 0 && smoothedSpeed == 0 && smoothedAcceleration == 0 && smoothedInertia == 0
        case .byLines:
            return scrollingDistanceInLines == 0
        case .byPixels:
            return scrollingDistanceInPixels == 0
        }
    }

    var modifiers: Scheme.Scrolling.Modifiers {
        get {
            mergedScheme.scrolling.modifiers[direction] ?? .init()
        }
        set {
            scheme.scrolling.modifiers[direction] = newValue
        }
    }

    var showsContinuousScrollShiftTip: Bool {
        direction == .vertical
            && scrollingMode.sendsContinuousScrollEvents
            && (modifiers.shift?.kind ?? .defaultAction) != .alterOrientation
    }

    func setShiftModifierToAlterOrientation() {
        var modifiers = modifiers
        modifiers.shift = .alterOrientation
        self.modifiers = modifiers
    }

    private var currentSmoothedConfiguration: Scheme.Scrolling.Smoothed? {
        let configuration = scheme.scrolling.smoothed[direction]
            ?? mergedScheme.scrolling.smoothed[direction]
            ?? smoothedCache[direction]
        guard configuration?.isEnabled == true else {
            return nil
        }
        return configuration
    }

    func smoothedPreviewConfiguration(for preset: Scheme.Scrolling.Smoothed.Preset) -> Scheme.Scrolling.Smoothed {
        if preset == .custom {
            var configuration = scheme.scrolling.smoothed[direction]
                ?? smoothedCache[direction]
                ?? currentSmoothedConfiguration
                ?? makeDefaultSmoothedConfiguration()
            configuration.enabled = true
            configuration.preset = .custom
            return configuration
        }

        return preset.defaultConfiguration
    }

    func restoreDefaultSmoothedPreset() {
        selectSmoothedPreset(.defaultPreset)
    }

    private func setSmoothedConfiguration(_ configuration: Scheme.Scrolling.Smoothed) {
        var configuration = configuration
        configuration.enabled = true
        scheme.scrolling.smoothed[direction] = configuration
        smoothedCache[direction] = configuration
    }

    private func clearSmoothedConfiguration() {
        if let currentSmoothedConfiguration {
            smoothedCache[direction] = currentSmoothedConfiguration
        }

        scheme.scrolling.smoothed[direction] = .init(enabled: false)
    }

    private func makeDefaultSmoothedConfiguration() -> Scheme.Scrolling.Smoothed {
        Scheme.Scrolling.Smoothed.Preset.defaultPreset.defaultConfiguration
    }

    private func selectSmoothedPreset(_ preset: Scheme.Scrolling.Smoothed.Preset) {
        if preset == .custom {
            setSmoothedConfiguration(makeCustomSmoothedConfiguration())
        } else {
            var configuration = preset.defaultConfiguration
            configuration.bouncing = makeEditableSmoothedConfiguration().allowsBouncing
            setSmoothedConfiguration(configuration)
        }
    }

    private func makeEditableSmoothedConfiguration() -> Scheme.Scrolling.Smoothed {
        var configuration = currentSmoothedConfiguration
            ?? scheme.scrolling.smoothed[direction]
            ?? smoothedCache[direction]
            ?? makeDefaultSmoothedConfiguration()
        configuration.enabled = true
        configuration.preset = configuration.preset ?? .defaultPreset
        return configuration
    }

    private func makeCustomSmoothedConfiguration() -> Scheme.Scrolling.Smoothed {
        var configuration = makeEditableSmoothedConfiguration()
        configuration.preset = .custom
        return configuration
    }

    private func updateSmoothedConfiguration(_ update: (inout Scheme.Scrolling.Smoothed) -> Void) {
        var configuration = makeEditableSmoothedConfiguration()
        update(&configuration)
        setSmoothedConfiguration(configuration)
    }

    private func decimalFormatter(maxFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfUp
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.thousandSeparator = ""
        return formatter
    }
}
