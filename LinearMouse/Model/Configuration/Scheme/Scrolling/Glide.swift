// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: SETTINGS
//
// Part of Glide scrolling. Overview: Documentation/Glide.md
//
// The `scrolling.glide` section of linearmouse.json, for example:
//
//     "glide": { "lines": 3, "lineHeight": 10, "duration": 180,
//                "curve": "easeOutCubic", "gameDetection": true }
//
// Every value is optional. A missing value means "use the default", or, in a
// per-app scheme, "inherit from the broader scheme" (see the merge functions).
//
// Contents
//   1. Glide           The stored settings, as read from the config file.
//   2. Defaults        Default values, allowed ranges, and the "resolved"
//                      values the engine uses (defaults filled in, clamped).
//   3. Merging         How per-app schemes override single values.
//   4. Curve details   Each curve's starting speed and its name in the UI.

import Foundation
import SwiftUI

// MARK: - 1. Glide

extension Scheme.Scrolling {
    /// Destination-based ("glide") smooth scrolling.
    ///
    /// Every wheel click moves a target by `lines × lineHeight` pixels. The
    /// page glides from its current position to that target over `duration`
    /// milliseconds using `curve`, and stops exactly on it. Clicks during a
    /// glide extend the target and keep the current speed instead of stacking
    /// momentum.
    struct Glide: Equatable, Codable, ImplicitInitable {
        /// The shape of the glide. The raw values are what the config file
        /// uses.
        enum Curve: String, Codable, Equatable, CaseIterable, Identifiable {
            var id: Self {
                self
            }

            /// Snappiest start, longest soft landing.
            case easeOutQuart
            /// Fast start, firm stop. The default.
            case easeOutCubic
            /// Gentler start than `easeOutCubic`.
            case easeOut
            /// Starts slowly from rest, like Chromium's initial animation.
            case easeInOut
        }

        /// `false` turns off a glide setting inherited from a broader scheme.
        var enabled: Bool?
        /// Lines moved per wheel click.
        var lines: Decimal?
        /// Pixels per line. macOS apps use about 10; Chromium uses 40.
        var lineHeight: Decimal?
        /// Glide duration in milliseconds.
        var duration: Decimal?
        /// Glide curve.
        var curve: Curve?
        /// While the cursor is hidden (how games capture the mouse), send one
        /// plain wheel click per notch instead of gliding.
        var gameDetection: Bool?

        init() {}

        init(
            enabled: Bool? = nil,
            lines: Decimal? = nil,
            lineHeight: Decimal? = nil,
            duration: Decimal? = nil,
            curve: Curve? = nil,
            gameDetection: Bool? = nil
        ) {
            self.enabled = enabled
            self.lines = lines
            self.lineHeight = lineHeight
            self.duration = duration
            self.curve = curve
            self.gameDetection = gameDetection
        }
    }
}

// MARK: - 2. Defaults

extension Scheme.Scrolling.Glide {
    static let defaultLines = 3.0
    /// The standard macOS line height.
    static let defaultLineHeight = 10.0
    /// Milliseconds. Chromium's wheel animations last 100 to 200 ms.
    static let defaultDuration = 180.0
    static let defaultCurve = Curve.easeOutCubic

    // Ranges for the settings sliders; config values are clamped to them too.
    static let linesRange: ClosedRange<Double> = 0.0 ... 20.0
    static let lineHeightRange: ClosedRange<Double> = 1.0 ... 100.0
    static let durationRange: ClosedRange<Double> = 30.0 ... 1000.0

    /// What "Restore defaults" in the settings and a fresh switch to Glide use.
    static var defaultConfiguration: Self {
        .init(
            enabled: true,
            lines: Decimal(defaultLines),
            lineHeight: Decimal(defaultLineHeight),
            duration: Decimal(defaultDuration),
            curve: defaultCurve,
            gameDetection: true
        )
    }

    // The "resolved" values below fill in defaults and keep values in range.
    // The engine only ever reads these.

    var isEnabled: Bool {
        enabled ?? true
    }

    var resolvedLines: Double {
        (lines?.asTruncatedDouble ?? Self.defaultLines).clamped(to: Self.linesRange)
    }

    var resolvedLineHeight: Double {
        (lineHeight?.asTruncatedDouble ?? Self.defaultLineHeight).clamped(to: Self.lineHeightRange)
    }

    /// Duration in seconds (the config stores milliseconds).
    var resolvedDuration: TimeInterval {
        (duration?.asTruncatedDouble ?? Self.defaultDuration).clamped(to: Self.durationRange) / 1000
    }

    var resolvedCurve: Curve {
        curve ?? Self.defaultCurve
    }

    /// Game detection is on unless turned off.
    var detectsGames: Bool {
        gameDetection ?? true
    }

    /// Distance in pixels for one wheel click. A nonzero distance is at least
    /// 1 pixel: smaller settings (for example 0.1 lines × 1 px) are reachable
    /// from the panel but would be too small to scroll at all.
    var pixelsPerDetent: Double {
        let pixels = resolvedLines * resolvedLineHeight
        return pixels > 0 ? max(pixels, 1) : 0
    }

    // MARK: - 3. Merging

    /// Copies every value that is set in `self` onto `glide`. Values that are
    /// not set are left as they are, so a per-app scheme can change one
    /// setting and inherit the rest.
    func merge(into glide: inout Self) {
        if let enabled {
            glide.enabled = enabled
        }

        if let lines {
            glide.lines = lines
        }

        if let lineHeight {
            glide.lineHeight = lineHeight
        }

        if let duration {
            glide.duration = duration
        }

        if let curve {
            glide.curve = curve
        }

        if let gameDetection {
            glide.gameDetection = gameDetection
        }
    }
}

extension Scheme.Scrolling {
    /// Merges glide settings per direction (vertical / horizontal), field by
    /// field, so a per-app scheme can override a single value (for example
    /// `lineHeight`) and inherit the rest. Called from `Scrolling.merge`.
    func merge(glide source: Bidirectional<Glide>?, into target: inout Bidirectional<Glide>) {
        guard let source else {
            return
        }

        if let sourceVertical = source.vertical {
            var merged = target.vertical ?? .init()
            sourceVertical.merge(into: &merged)
            target.vertical = merged
        }

        if let sourceHorizontal = source.horizontal {
            var merged = target.horizontal ?? .init()
            sourceHorizontal.merge(into: &merged)
            target.horizontal = merged
        }
    }
}

// MARK: - 4. Curve details

extension Scheme.Scrolling.Glide.Curve {
    /// How fast the curve starts, 0 ... 4 (`a` in `GlideCurve`, in
    /// GlideScrollingEngine.swift).
    var initialSlope: Double {
        switch self {
        case .easeOutQuart:
            return 4
        case .easeOutCubic:
            return 3
        case .easeOut:
            return 2
        case .easeInOut:
            return 0
        }
    }

    /// Name shown in the settings window.
    var title: LocalizedStringKey {
        switch self {
        case .easeOutQuart:
            return "Ease Out Quart"
        case .easeOutCubic:
            return "Ease Out Cubic"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease In Out"
        }
    }
}
