// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ScrollingModeSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared
        @State private var isContinuousScrollTipPresented = false

        var body: some View {
            Section {
                HStack(spacing: 8) {
                    Picker("Scrolling mode", selection: $state.scrollingMode) {
                        ForEach(ScrollingSettingsState.ScrollingMode.allCases) { scrollingMode in
                            Text(scrollingMode.label).tag(scrollingMode)
                        }
                    }
                    .modifier(PickerViewModifier())

                    if state.showsContinuousScrollShiftTip {
                        Button {
                            isContinuousScrollTipPresented.toggle()
                        } label: {
                            Text(verbatim: "ⓘ")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .popover(isPresented: $isContinuousScrollTipPresented, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(
                                    "To enable horizontal scrolling with Shift, set Shift to Alter orientation in Modifier Keys."
                                )
                                .fixedSize(horizontal: false, vertical: true)

                                HStack(alignment: .firstTextBaseline) {
                                    HyperLink(
                                        URL(
                                            string: "https://github.com/linearmouse/linearmouse/issues/1180#issuecomment-4461761262"
                                        )!
                                    ) {
                                        Text("Learn more")
                                    }

                                    Spacer()

                                    Button("Enable") {
                                        state.setShiftModifierToAlterOrientation()
                                        isContinuousScrollTipPresented = false
                                    }
                                }
                            }
                            .padding()
                            .frame(width: 280, alignment: .leading)
                        }
                    }
                }

                switch state.scrollingMode {
                case .accelerated:
                    HStack(alignment: .firstTextBaseline) {
                        Slider(
                            value: $state.scrollingAcceleration,
                            in: 0.0 ... 10.0
                        ) {
                            labelWithDescription {
                                Text("Scrolling acceleration")
                                Text(verbatim: "(0–10)")
                            }
                        } minimumValueLabel: {
                            Text("Linear")
                        } maximumValueLabel: {
                            Text("Accelerated")
                        }
                        TextField(
                            String(""),
                            value: $state.scrollingAcceleration,
                            formatter: state.scrollingAccelerationFormatter
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Slider(
                            value: $state.scrollingSpeed,
                            in: 0.0 ... 128.0
                        ) {
                            labelWithDescription {
                                Text("Scrolling speed")
                                Text(verbatim: "(0–128)")
                            }
                        } minimumValueLabel: {
                            Text("Slow")
                        } maximumValueLabel: {
                            Text("Fast")
                        }
                        TextField(
                            String(""),
                            value: $state.scrollingSpeed,
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

                case .smoothed:
                    ScrollingSettings.SmoothedScrollingSection()

                case .byLines:
                    Slider(
                        value: $state.scrollingDistanceInLines,
                        in: 0 ... 10,
                        step: 1
                    ) {
                        Text("Distance")
                    } minimumValueLabel: {
                        Text(verbatim: "0")
                    } maximumValueLabel: {
                        Text(verbatim: "10")
                    }

                case .byPixels:
                    Slider(
                        value: $state.scrollingDistanceInPixels,
                        in: 0 ... 128
                    ) {
                        Text("Distance")
                    } minimumValueLabel: {
                        Text(verbatim: "0px")
                    } maximumValueLabel: {
                        Text(verbatim: "128px")
                    }
                }
            }
            .modifier(SectionViewModifier())
        }
    }
}
