// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Combine
import Foundation
import PublishedObject
import SwiftUI

class ButtonsSettingsState: ObservableObject {
    static let shared: ButtonsSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    var scheme: Scheme {
        get { schemeState.scheme }
        set { schemeState.scheme = newValue }
    }

    var mergedScheme: Scheme { schemeState.mergedScheme }
}

extension ButtonsSettingsState {
    var universalBackForward: Bool {
        get {
            mergedScheme.buttons.universalBackForward ?? .none != .none
        }
        set {
            scheme.buttons.universalBackForward = .some(newValue ? .both : .none)
        }
    }

    var switchPrimaryAndSecondaryButtons: Bool {
        get {
            mergedScheme.buttons.switchPrimaryButtonAndSecondaryButtons ?? false
        }
        set {
            scheme.buttons.switchPrimaryButtonAndSecondaryButtons = newValue
        }
    }

    var clickDebouncingEnabled: Bool {
        get {
            mergedScheme.buttons.clickDebouncing.timeout ?? 0 > 0
        }
        set {
            scheme.buttons.clickDebouncing.timeout = newValue ? 50 : 0
        }
    }

    var clickDebouncingTimeout: Int {
        get {
            mergedScheme.buttons.clickDebouncing.timeout ?? 0
        }
        set {
            scheme.buttons.clickDebouncing.timeout = newValue
        }
    }

    var clickDebouncingTimeoutInDouble: Double {
        get {
            Double(clickDebouncingTimeout)
        }
        set {
            clickDebouncingTimeout = newValue <= 10 ? Int(round(newValue)) : Int(round(newValue / 10)) * 10
        }
    }

    var clickDebouncingTimeoutFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 0
        formatter.thousandSeparator = ""
        formatter.minimum = 5
        formatter.maximum = 500
        return formatter
    }

    var clickDebouncingResetTimerOnMouseUp: Bool {
        get {
            mergedScheme.buttons.clickDebouncing.resetTimerOnMouseUp ?? false
        }
        set {
            scheme.buttons.clickDebouncing.resetTimerOnMouseUp = newValue
        }
    }

    func clickDebouncingButtonEnabledBinding(for button: CGMouseButton) -> Binding<Bool> {
        Binding<Bool>(
            get: { [self] in
                (mergedScheme.buttons.clickDebouncing.buttons ?? []).contains(button)
            },
            set: { [self] newValue in
                let buttons = mergedScheme.buttons.clickDebouncing.buttons ?? []
                if newValue {
                    scheme.buttons.clickDebouncing.buttons = buttons + [button]
                } else {
                    scheme.buttons.clickDebouncing.buttons = buttons.filter { $0 != button }
                }
            }
        )
    }

    var mappings: [Scheme.Buttons.Mapping] {
        get { scheme.buttons.mappings ?? [] }
        set { scheme.buttons.mappings = newValue }
    }

    func appendMapping(_ mapping: Scheme.Buttons.Mapping) {
        mappings = (mappings + [mapping]).sorted()
    }
}
