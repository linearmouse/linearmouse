// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Combine
import Foundation
import PublishedObject

class PointerSettingsState: ObservableObject {
    static let shared: PointerSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    var scheme: Scheme {
        get { schemeState.scheme }
        set { schemeState.scheme = newValue }
    }

    var mergedScheme: Scheme { schemeState.mergedScheme }
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
