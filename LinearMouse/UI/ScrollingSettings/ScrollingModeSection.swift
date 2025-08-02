// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ScrollingModeSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Picker("Scrolling mode", selection: scrollingModeBinding) {
                    ForEach(ScrollingSettingsState.ScrollingMode.allCases) { scrollingMode in
                        Text(NSLocalizedString(scrollingMode.rawValue, comment: "")).tag(scrollingMode)
                    }
                }
                .modifier(PickerViewModifier())

                switch state.scrollingMode {
                case .accelerated:
                    HStack(alignment: .firstTextBaseline) {
                        Slider(
                            value: scrollingAccelerationBinding,
                            in: 0.0 ... 10.0
                        ) {
                            labelWithDescription {
                                Text("Scrolling acceleration")
                                Text("(0–10)")
                            }
                        } minimumValueLabel: {
                            Text("Linear")
                        } maximumValueLabel: {
                            Text("Accelerated")
                        }
                        TextField(
                            "",
                            value: scrollingAccelerationBinding,
                            formatter: state.scrollingAccelerationFormatter
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Slider(
                            value: scrollingSpeedBinding,
                            in: 0.0 ... 128.0
                        ) {
                            labelWithDescription {
                                Text("Scrolling speed")
                                Text("(0–128)")
                            }
                        } minimumValueLabel: {
                            Text("Slow")
                        } maximumValueLabel: {
                            Text("Fast")
                        }
                        TextField(
                            "",
                            value: scrollingSpeedBinding,
                            formatter: state.scrollingSpeedFormatter
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    }

                    if state.scrollingDisabled {
                        Text("Scrolling is disabled based on the current settings.")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button("Revert to system defaults") {
                            DispatchQueue.main.async {
                                state.scrollingMode = .accelerated
                                state.scrollingAcceleration = 1
                                state.scrollingSpeed = 0
                            }
                        }

                        if state.direction == .horizontal {
                            Button("Copy settings from vertical") {
                                DispatchQueue.main.async {
                                    state.scheme.scrolling.distance.horizontal = state.mergedScheme.scrolling.distance
                                        .vertical
                                    state.scheme.scrolling.acceleration.horizontal = state.mergedScheme.scrolling
                                        .acceleration
                                        .vertical
                                    state.scheme.scrolling.speed.horizontal = state.mergedScheme.scrolling.speed
                                        .vertical
                                }
                            }
                        }
                    }

                case .byLines:
                    Slider(
                        value: scrollingDistanceInLinesBinding,
                        in: 0 ... 10,
                        step: 1
                    ) {
                        Text("Distance")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("10")
                    }

                case .byPixels:
                    Slider(
                        value: scrollingDistanceInPixelsBinding,
                        in: 0 ... 128
                    ) {
                        Text("Distance")
                    } minimumValueLabel: {
                        Text("0px")
                    } maximumValueLabel: {
                        Text("128px")
                    }
                }
            }
            .modifier(SectionViewModifier())
        }

        // MARK: - Bindings

        private var scrollingModeBinding: Binding<ScrollingSettingsState.ScrollingMode> {
            Binding(
                get: { state.scrollingMode },
                set: { newValue in
                    DispatchQueue.main.async {
                        state.scrollingMode = newValue
                    }
                }
            )
        }

        private var scrollingAccelerationBinding: Binding<Double> {
            Binding(
                get: { state.scrollingAcceleration },
                set: { newValue in
                    DispatchQueue.main.async {
                        state.scrollingAcceleration = newValue
                    }
                }
            )
        }

        private var scrollingSpeedBinding: Binding<Double> {
            Binding(
                get: { state.scrollingSpeed },
                set: { newValue in
                    DispatchQueue.main.async {
                        state.scrollingSpeed = newValue
                    }
                }
            )
        }

        private var scrollingDistanceInLinesBinding: Binding<Double> {
            Binding(
                get: { state.scrollingDistanceInLines },
                set: { newValue in
                    DispatchQueue.main.async {
                        state.scrollingDistanceInLines = newValue
                    }
                }
            )
        }

        private var scrollingDistanceInPixelsBinding: Binding<Double> {
            Binding(
                get: { state.scrollingDistanceInPixels },
                set: { newValue in
                    DispatchQueue.main.async {
                        state.scrollingDistanceInPixels = newValue
                    }
                }
            )
        }
    }
}
