// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation
import PublishedObject

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

    var debounceClicksEnabled: Bool {
        get {
            mergedScheme.buttons.debounceClicks ?? 0 > 0
        }
        set {
            scheme.buttons.debounceClicks = newValue ? 50 : 0
        }
    }

    var debounceClicks: Int {
        get {
            mergedScheme.buttons.debounceClicks ?? 0
        }
        set {
            scheme.buttons.debounceClicks = newValue
        }
    }

    var debounceClicksInDouble: Double {
        get {
            Double(debounceClicks)
        }
        set {
            debounceClicks = Int(round(newValue / 10)) * 10
        }
    }

    var debounceClicksFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 0
        formatter.thousandSeparator = ""
        formatter.minimum = 10
        formatter.maximum = 500
        return formatter
    }
}
