// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

extension ScrollingSettings {
    struct ScrollingModeSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Picker("Mode", selection: $state.scrollingMode) {
                    ForEach(ScrollingSettingsState.ScrollingMode.allCases) { scrollingMode in
                        Text(NSLocalizedString(scrollingMode.rawValue, comment: "")).tag(scrollingMode)
                    }
                }
                .modifier(PickerViewModifier())

                switch state.scrollingMode {
                case .accelerated:
                    Slider(value: $state.scrollingAcceleration,
                           in: 0.0 ... 10.0) {
                        Text("Acceleration")
                    } minimumValueLabel: {
                        Text("Linear")
                    } maximumValueLabel: {
                        Text("Accelerated")
                    }

                    Slider(value: $state.scrollingSpeed,
                           in: 0.0 ... 128.0) {
                        Text("Speed")
                    } minimumValueLabel: {
                        Text("Slow")
                    } maximumValueLabel: {
                        Text("Fast")
                    }

                    HStack(spacing: 10) {
                        Spacer()

                        Button("Revert to system defaults") {
                            state.scrollingMode = .accelerated
                            state.scrollingAcceleration = 1
                            state.scrollingSpeed = 0
                        }

                        if state.direction == .horizontal {
                            Button("Copy settings from vertical") {
                                state.scheme.scrolling.distance.horizontal = state.scheme.scrolling.distance.vertical
                                state.scheme.scrolling.acceleration.horizontal = state.scheme.scrolling.acceleration
                                    .vertical
                                state.scheme.scrolling.speed.horizontal = state.scheme.scrolling.speed.vertical
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
