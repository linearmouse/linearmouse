// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ScrollingModeSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Picker("Scrolling mode", selection: $state.scrollingMode) {
                    ForEach(ScrollingSettingsState.ScrollingMode.allCases) { scrollingMode in
                        Text(NSLocalizedString(scrollingMode.rawValue, comment: "")).tag(scrollingMode)
                    }
                }
                .modifier(PickerViewModifier())

                switch state.scrollingMode {
                case .accelerated:
                    HStack(alignment: .firstTextBaseline) {
                        Slider(value: $state.scrollingAcceleration,
                               in: 0.0 ... 10.0) {
                            labelWithDescription {
                                Text("Scrolling acceleration")
                                Text("(0–10)")
                            }
                        } minimumValueLabel: {
                            Text("Linear")
                        } maximumValueLabel: {
                            Text("Accelerated")
                        }
                        TextField("",
                                  value: $state.scrollingAcceleration,
                                  formatter: state.scrollingAccelerationFormatter)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Slider(value: $state.scrollingSpeed,
                               in: 0.0 ... 128.0) {
                            labelWithDescription {
                                Text("Scrolling speed")
                                Text("(0–128)")
                            }
                        } minimumValueLabel: {
                            Text("Slow")
                        } maximumValueLabel: {
                            Text("Fast")
                        }
                        TextField("",
                                  value: $state.scrollingSpeed,
                                  formatter: state.scrollingSpeedFormatter)
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
                            state.scrollingMode = .accelerated
                            state.scrollingAcceleration = 1
                            state.scrollingSpeed = 0
                        }

                        if state.direction == .horizontal {
                            Button("Copy settings from vertical") {
                                state.scheme.scrolling.distance.horizontal = state.mergedScheme.scrolling.distance
                                    .vertical
                                state.scheme.scrolling.acceleration.horizontal = state.mergedScheme.scrolling
                                    .acceleration
                                    .vertical
                                state.scheme.scrolling.speed.horizontal = state.mergedScheme.scrolling.speed.vertical
                            }
                        }
                    }

                case .byLines:
                    Slider(
                        value: $state.scrollingDistanceInLines,
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
                        value: $state.scrollingDistanceInPixels,
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
    }
}
