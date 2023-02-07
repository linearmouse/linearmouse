// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

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
}

extension PointerSettingsState {
    var pointerAcceleration: Double {
        get {
            scheme.pointer.acceleration?.asTruncatedDouble
                ?? scheme.firstMatchedDevice?.pointerAcceleration
                ?? Device.fallbackPointerAcceleration
        }
        set {
            guard abs(pointerAcceleration - newValue) >= 0.0001 else {
                return
            }

            scheme.pointer.acceleration = Decimal(newValue).rounded(4)
        }
    }

    var pointerSpeed: Double {
        get {
            scheme.pointer.speed?.asTruncatedDouble
                ?? scheme.firstMatchedDevice?.pointerSpeed
                ?? Device.fallbackPointerSpeed
        }
        set {
            guard abs(pointerSpeed - newValue) >= 0.0001 else {
                return
            }

            scheme.pointer.speed = Decimal(newValue).rounded(4)
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

    var pointerDisableAcceleration: Bool {
        get {
            scheme.pointer.disableAcceleration ?? false
        }
        set {
            scheme.pointer.disableAcceleration = newValue
        }
    }

    func revertPointerSpeed() {
        let device = scheme.firstMatchedDevice

        device?.restorePointerAccelerationAndPointerSpeed()

        Scheme(
            pointer: Scheme.Pointer(
                acceleration: Decimal(device?.pointerAcceleration ?? Device.fallbackPointerAcceleration),
                speed: Decimal(device?.pointerSpeed ?? Device.fallbackPointerSpeed),
                disableAcceleration: false
            )
        )
        .merge(into: &scheme)
    }
}
