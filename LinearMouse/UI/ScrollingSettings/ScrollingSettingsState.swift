// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import PublishedObject
import SwiftUI

class ScrollingSettingsState: ObservableObject {
    static let shared: ScrollingSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    private var smoothedCache = Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>()

    var scheme: Scheme {
        get { schemeState.scheme }
        set { schemeState.scheme = newValue }
    }

    var mergedScheme: Scheme {
        schemeState.mergedScheme
    }

    @Published var direction: Scheme.Scrolling.BidirectionalDirection = .vertical
}

extension ScrollingSettingsState {
    var reverseScrolling: Bool {
        get { mergedScheme.scrolling.reverse[direction] ?? false }
        set { scheme.scrolling.reverse[direction] = newValue }
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
            case .accelerated: "Accelerated"
            case .smoothed: "Smoothed (Beta)"
            case .byLines: "By Lines"
            case .byPixels: "By Pixels"
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
