// MIT License
// Copyright (c) 2021-2026 LinearMouse

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

    var mergedScheme: Scheme {
        schemeState.mergedScheme
    }
}

extension ButtonsSettingsState {
    private var defaultAutoScrollModes: [Scheme.Buttons.AutoScroll.Mode] {
        [.toggle]
    }

    private var defaultAutoScrollTrigger: Scheme.Buttons.Mapping {
        var mapping = Scheme.Buttons.Mapping()
        mapping.button = .mouse(Int(CGMouseButton.center.rawValue))
        return mapping
    }

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

    var autoScrollEnabled: Bool {
        get {
            mergedScheme.buttons.autoScroll.enabled ?? false
        }
        set {
            guard newValue != autoScrollEnabled else {
                return
            }

            if newValue {
                scheme.buttons.autoScroll.enabled = true
                if scheme.buttons.autoScroll.trigger == nil {
                    scheme.buttons.autoScroll.trigger = defaultAutoScrollTrigger
                }
                if scheme.buttons.autoScroll.modes == nil {
                    scheme.buttons.autoScroll.modes = defaultAutoScrollModes
                }
                if scheme.buttons.autoScroll.speed == nil {
                    scheme.buttons.autoScroll.speed = 1
                }
                if scheme.buttons.autoScroll.preserveNativeMiddleClick == nil {
                    scheme.buttons.autoScroll.preserveNativeMiddleClick = true
                }
            } else {
                scheme.buttons.autoScroll.enabled = false
            }

            GlobalEventTap.shared.stop()
            GlobalEventTap.shared.start()
        }
    }

    var autoScrollModes: [Scheme.Buttons.AutoScroll.Mode] {
        get {
            mergedScheme.buttons.autoScroll.normalizedModes
        }
        set {
            let orderedModes = Scheme.Buttons.AutoScroll.Mode.allCases.filter { newValue.contains($0) }
            scheme.buttons.autoScroll.modes = orderedModes.isEmpty ? defaultAutoScrollModes : orderedModes
        }
    }

    var autoScrollToggleModeEnabled: Bool {
        get {
            autoScrollModes.contains(.toggle)
        }
        set {
            var modes = Set(autoScrollModes)
            if newValue {
                modes.insert(.toggle)
            } else {
                modes.remove(.toggle)
            }
            autoScrollModes = Array(modes)
        }
    }

    var autoScrollHoldModeEnabled: Bool {
        get {
            autoScrollModes.contains(.hold)
        }
        set {
            var modes = Set(autoScrollModes)
            if newValue {
                modes.insert(.hold)
            } else {
                modes.remove(.hold)
            }
            autoScrollModes = Array(modes)
        }
    }

    var autoScrollSpeed: Double {
        get {
            mergedScheme.buttons.autoScroll.speed?.asTruncatedDouble ?? 1
        }
        set {
            scheme.buttons.autoScroll.speed = Decimal(newValue).rounded(1)
        }
    }

    var autoScrollSpeedText: String {
        String(format: "%.1fx", autoScrollSpeed)
    }

    var autoScrollPreserveNativeMiddleClick: Bool {
        get {
            mergedScheme.buttons.autoScroll.preserveNativeMiddleClick ?? true
        }
        set {
            scheme.buttons.autoScroll.preserveNativeMiddleClick = newValue
        }
    }

    var autoScrollTrigger: Scheme.Buttons.Mapping {
        get {
            mergedScheme.buttons.autoScroll.trigger ?? defaultAutoScrollTrigger
        }
        set {
            var trigger = newValue
            trigger.action = nil
            trigger.repeat = nil
            trigger.scroll = nil
            scheme.buttons.autoScroll.trigger = trigger
        }
    }

    var autoScrollTriggerBinding: Binding<Scheme.Buttons.Mapping> {
        Binding(
            get: { [self] in
                autoScrollTrigger
            },
            set: { [self] in
                autoScrollTrigger = $0
            }
        )
    }

    var autoScrollTriggerValid: Bool {
        autoScrollTrigger.valid
    }

    var autoScrollUsesPlainMiddleClick: Bool {
        let trigger = autoScrollTrigger
        return trigger.button == .mouse(Int(CGMouseButton.center.rawValue)) && trigger.modifierFlags.isEmpty
    }

    var autoScrollPreserveNativeMiddleClickAvailable: Bool {
        autoScrollUsesPlainMiddleClick && autoScrollToggleModeEnabled
    }

    var mappings: [Scheme.Buttons.Mapping] {
        get { scheme.buttons.mappings ?? [] }
        set { scheme.buttons.mappings = newValue }
    }

    func appendMapping(_ mapping: Scheme.Buttons.Mapping) {
        mappings = (mappings + [mapping]).sorted()
    }

    var gestureEnabled: Bool {
        get {
            mergedScheme.buttons.gesture.enabled ?? false
        }
        set {
            if newValue {
                scheme.buttons.gesture.enabled = true
                scheme.buttons.gesture.button = 2
                scheme.buttons.gesture.threshold = 50
                scheme.buttons.gesture.actions.left = .spaceLeft
                scheme.buttons.gesture.actions.right = .spaceRight
                scheme.buttons.gesture.actions.up = .missionControl
                scheme.buttons.gesture.actions.down = .appExpose
            } else {
                scheme.buttons.$gesture = nil
            }
        }
    }

    var gestureButton: Int {
        get {
            mergedScheme.buttons.gesture.button ?? 2
        }
        set {
            scheme.buttons.gesture.button = newValue
        }
    }

    var gestureThreshold: Int {
        get {
            mergedScheme.buttons.gesture.threshold ?? 50
        }
        set {
            scheme.buttons.gesture.threshold = newValue
        }
    }

    var gestureThresholdDouble: Double {
        get {
            Double(gestureThreshold)
        }
        set {
            gestureThreshold = Int(round(newValue / 5)) * 5
        }
    }

    var gestureActionLeft: Scheme.Buttons.Gesture.GestureAction {
        get {
            mergedScheme.buttons.gesture.actions.left ?? .spaceLeft
        }
        set {
            scheme.buttons.gesture.actions.left = newValue
        }
    }

    var gestureActionRight: Scheme.Buttons.Gesture.GestureAction {
        get {
            mergedScheme.buttons.gesture.actions.right ?? .spaceRight
        }
        set {
            scheme.buttons.gesture.actions.right = newValue
        }
    }

    var gestureActionUp: Scheme.Buttons.Gesture.GestureAction {
        get {
            mergedScheme.buttons.gesture.actions.up ?? .missionControl
        }
        set {
            scheme.buttons.gesture.actions.up = newValue
        }
    }

    var gestureActionDown: Scheme.Buttons.Gesture.GestureAction {
        get {
            mergedScheme.buttons.gesture.actions.down ?? .appExpose
        }
        set {
            scheme.buttons.gesture.actions.down = newValue
        }
    }
}
