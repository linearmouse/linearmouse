// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

class PointerSettingsState: CurrentConfigurationState {}

extension PointerSettingsState {
    var pointerAcceleration: Double {
        get {
            scheme.pointer?.acceleration.map(\.asTruncatedDouble)
                ?? scheme.firstMatchedDevice?.pointerAcceleration
                ?? Device.fallbackPointerAcceleration
        }
        set {
            guard abs(pointerAcceleration - newValue) >= 0.0001 else {
                return
            }

            Scheme(
                pointer: Scheme.Pointer(
                    acceleration: Decimal(newValue).rounded(4)
                )
            )
            .merge(into: &scheme)
        }
    }

    var pointerSpeed: Double {
        get {
            scheme.pointer?.speed.map(\.asTruncatedDouble)
                ?? scheme.firstMatchedDevice?.pointerSensitivity
                ?? Device.fallbackPointerSpeed
        }
        set {
            guard abs(pointerSpeed - newValue) >= 0.01 else {
                return
            }

            Scheme(
                pointer: Scheme.Pointer(
                    speed: Decimal(newValue).rounded(2)
                )
            )
            .merge(into: &scheme)
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
        formatter.maximumFractionDigits = 2
        formatter.thousandSeparator = ""
        return formatter
    }

    var pointerDisableAcceleration: Bool {
        get {
            scheme.pointer?.disableAcceleration ?? false
        }
        set {
            Scheme(
                pointer: Scheme.Pointer(
                    disableAcceleration: newValue
                )
            )
            .merge(into: &scheme)
        }
    }

    func revertPointerSpeed() {
        let device = scheme.firstMatchedDevice

        device?.restorePointerSpeedToInitialValue()

        Scheme(
            pointer: Scheme.Pointer(
                acceleration: Decimal(device?.pointerAcceleration ?? Device.fallbackPointerAcceleration),
                speed: Decimal(device?.pointerSensitivity ?? Device.fallbackPointerSpeed),
                disableAcceleration: false
            )
        )
        .merge(into: &scheme)
    }
}
