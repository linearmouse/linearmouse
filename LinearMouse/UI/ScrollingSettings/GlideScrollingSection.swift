// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: SETTINGS PANEL
//
// Part of Glide scrolling. Overview: Documentation/Glide.md
//
// The panel shown under Scrolling when the scrolling mode is "Glide":
// a curve picker, sliders for distance per click, line height and glide
// duration, the "Detect games" switch, and two buttons. The values come from
// ScrollingSettingsState+Glide.swift. Shown by ScrollingModeSection.

import SwiftUI

extension ScrollingSettings {
    struct GlideScrollingSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                withDescription {
                    Text("Glide")
                    Text("Each wheel click moves a target. The page glides there and stops exactly on it.")
                }

                // Curve picker.
                Picker("Curve", selection: Binding(
                    get: { state.glideCurve },
                    set: { state.glideCurve = $0 }
                )) {
                    ForEach(Scheme.Scrolling.Glide.Curve.allCases) { curve in
                        Text(curve.title).tag(curve)
                    }
                }
                .modifier(PickerViewModifier())

                // How far one wheel click scrolls: lines × line height.
                sliderRow(
                    title: "Distance per click",
                    description: "(lines)",
                    value: Binding(
                        get: { state.glideLines },
                        set: { state.glideLines = $0 }
                    ),
                    range: Scheme.Scrolling.Glide.linesRange,
                    minimumValueLabel: "0",
                    maximumValueLabel: "20"
                )

                sliderRow(
                    title: "Line height",
                    description: "(pixels per line)",
                    value: Binding(
                        get: { state.glideLineHeight },
                        set: { state.glideLineHeight = $0 }
                    ),
                    range: Scheme.Scrolling.Glide.lineHeightRange,
                    minimumValueLabel: "1",
                    maximumValueLabel: "100"
                )

                // How long each glide lasts after the latest click.
                sliderRow(
                    title: "Glide duration",
                    description: "(ms)",
                    value: Binding(
                        get: { state.glideDuration },
                        set: { state.glideDuration = $0 }
                    ),
                    range: Scheme.Scrolling.Glide.durationRange,
                    minimumValueLabel: "Snappy",
                    maximumValueLabel: "Slow"
                )

                // One plain wheel click per notch while a game hides the cursor.
                Toggle(isOn: Binding(
                    get: { state.glideGameDetection },
                    set: { state.glideGameDetection = $0 }
                )) {
                    withDescription {
                        Text("Detect games")
                        Text("When a game hides the cursor, send one wheel click per notch instead of gliding.")
                    }
                }

                HStack(spacing: 10) {
                    Button("Restore defaults") {
                        state.restoreDefaultGlideConfiguration()
                    }

                    if state.direction == .horizontal {
                        Button("Copy settings from vertical") {
                            state.copyGlideConfigurationFromVertical()
                        }
                    }
                }
            }
        }

        /// A labelled slider with a number box beside it, matching the Smoothed
        /// panel's layout.
        private func sliderRow(
            title: LocalizedStringKey,
            description: String,
            value: Binding<Double>,
            range: ClosedRange<Double>,
            minimumValueLabel: LocalizedStringKey,
            maximumValueLabel: LocalizedStringKey
        ) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Slider(
                    value: value,
                    in: range
                ) {
                    labelWithDescription {
                        Text(title)
                        Text(verbatim: description)
                    }
                } minimumValueLabel: {
                    Text(minimumValueLabel)
                } maximumValueLabel: {
                    Text(maximumValueLabel)
                }

                DeferredNumberField(
                    value: value,
                    formatter: state.glideFormatter,
                    range: range
                )
                .frame(width: 60, height: 22)
            }
        }
    }
}
