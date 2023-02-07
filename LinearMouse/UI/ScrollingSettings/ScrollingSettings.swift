// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ScrollingSettings: View {
    @ObservedObject var state = ScrollingSettingsState.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()

                    Picker("", selection: $state.direction) {
                        ForEach(Scheme.Scrolling.BidirectionalDirection.allCases) { direction in
                            Text(NSLocalizedString(direction.rawValue, comment: "")).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    Spacer()
                }
                .padding(.top, 20)

                Form {
                    Section {
                        Toggle(isOn: $state.reverseScrolling) {
                            withDescription {
                                Text("Reverse scrolling")
                                if state.direction == .horizontal {
                                    Text("Some gestures, such as swiping back and forward, may stop working.")
                                }
                            }
                        }
                    }
                    .modifier(SectionViewModifier())

                    Section {
                        Picker("Mode", selection: $state.scrollingMode) {
                            ForEach(ScrollingSettingsState.ScrollingMode.allCases) { scrollingMode in
                                Text(NSLocalizedString(scrollingMode.rawValue, comment: "")).tag(scrollingMode)
                            }
                        }
                        .modifier(PickerViewModifier())

                        switch state.scrollingMode {
                        case .accelerated:
                            Slider(value: $state.scrollingScale,
                                   in: 0.0 ... 10.0) {
                                Text("Speed")
                            } minimumValueLabel: {
                                Text("Slower")
                            } maximumValueLabel: {
                                Text("Faster")
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
                .modifier(FormViewModifier())
            }
        }
    }
}
