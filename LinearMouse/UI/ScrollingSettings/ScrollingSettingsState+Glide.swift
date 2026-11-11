// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: SETTINGS WINDOW STATE
//
// Part of Glide scrolling. Overview: Documentation/Glide.md
//
// Connects the Glide panel in the Scrolling settings (GlideScrollingSection)
// to the configuration. Each property reads the effective value (this scheme
// merged with broader ones) and writes changes into the scheme being edited.
// `direction` is the Vertical / Horizontal tab currently selected.
//
// Contents
//   1. Current values   One property per control in the Glide panel.
//   2. Mode switching   Turning Glide on or off when the scrolling mode
//                       picker changes (called from ScrollingSettingsState).
//   3. Buttons          "Restore defaults" and "Copy settings from vertical".

import Foundation

extension ScrollingSettingsState {
    // MARK: - 1. Current values

    /// The effective glide settings for the selected direction, or `nil` if
    /// Glide is off there.
    var currentGlideConfiguration: Scheme.Scrolling.Glide? {
        guard let configuration = mergedScheme.scrolling.glide[direction],
              configuration.isEnabled else {
            return nil
        }
        return configuration
    }

    /// "Distance per click" slider, in lines.
    var glideLines: Double {
        get { currentGlideConfiguration?.resolvedLines ?? Scheme.Scrolling.Glide.defaultLines }
        set { updateGlideConfiguration { $0.lines = Decimal(newValue).rounded(1) } }
    }

    /// "Line height" slider, in pixels.
    var glideLineHeight: Double {
        get { currentGlideConfiguration?.resolvedLineHeight ?? Scheme.Scrolling.Glide.defaultLineHeight }
        set { updateGlideConfiguration { $0.lineHeight = Decimal(newValue).rounded(1) } }
    }

    /// "Glide duration" slider, in milliseconds (stored as seconds once
    /// resolved, so it is converted back here).
    var glideDuration: Double {
        get {
            (currentGlideConfiguration?.resolvedDuration).map { $0 * 1000 }
                ?? Scheme.Scrolling.Glide.defaultDuration
        }
        set { updateGlideConfiguration { $0.duration = Decimal(newValue).rounded(0) } }
    }

    /// "Curve" picker.
    var glideCurve: Scheme.Scrolling.Glide.Curve {
        get { currentGlideConfiguration?.resolvedCurve ?? Scheme.Scrolling.Glide.defaultCurve }
        set { updateGlideConfiguration { $0.curve = newValue } }
    }

    /// "Detect games" switch.
    var glideGameDetection: Bool {
        get { currentGlideConfiguration?.detectsGames ?? true }
        set { updateGlideConfiguration { $0.gameDetection = newValue } }
    }

    /// Formats the number boxes next to the sliders (up to one decimal).
    var glideFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfUp
        formatter.maximumFractionDigits = 1
        formatter.thousandSeparator = ""
        return formatter
    }

    // MARK: - 2. Mode switching

    /// Turns glide on for the current direction, keeping any values already
    /// set in this scheme or inherited from another one.
    func enableGlideConfiguration() {
        var configuration = scheme.scrolling.glide[direction] ?? .init()
        if mergedScheme.scrolling.glide[direction] == nil {
            // Nothing to inherit: start from the defaults.
            configuration = .defaultConfiguration
        }
        configuration.enabled = true
        scheme.scrolling.glide[direction] = configuration
    }

    /// Turns glide off for the current direction if it is on.
    func clearGlideConfiguration() {
        guard currentGlideConfiguration != nil else {
            return
        }
        var configuration = scheme.scrolling.glide[direction] ?? .init()
        configuration.enabled = false
        scheme.scrolling.glide[direction] = configuration
    }

    // MARK: - 3. Buttons

    /// "Restore defaults" button.
    func restoreDefaultGlideConfiguration() {
        scheme.scrolling.glide[direction] = .defaultConfiguration
    }

    /// "Copy settings from vertical" button (shown on the Horizontal tab).
    /// Unset vertical values are copied as their defaults, so a value
    /// inherited by Horizontal from a broader scheme cannot show through.
    func copyGlideConfigurationFromVertical() {
        guard let vertical = mergedScheme.scrolling.glide.vertical else {
            scheme.scrolling.glide.horizontal = nil
            return
        }
        var copied = Scheme.Scrolling.Glide.defaultConfiguration
        vertical.merge(into: &copied)
        scheme.scrolling.glide.horizontal = copied
    }

    /// Applies a change from the panel to the scheme being edited. Changing
    /// any Glide control also turns Glide on for this direction.
    private func updateGlideConfiguration(_ update: (inout Scheme.Scrolling.Glide) -> Void) {
        var configuration = scheme.scrolling.glide[direction] ?? .init()
        configuration.enabled = true
        update(&configuration)
        scheme.scrolling.glide[direction] = configuration
    }
}
