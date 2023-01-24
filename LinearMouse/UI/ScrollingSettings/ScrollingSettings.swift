// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ScrollingSettings: View {
    @ObservedObject var state = State.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()

                    Picker("", selection: $state.orientation) {
                        Text("Vertical").tag(State.Orientation.vertical)
                        Text("Horizontal").tag(State.Orientation.horizontal)
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
                                if state.orientation == .horizontal {
                                    Text("Some gestures, such as swiping back and forward, may stop working.")
                                }
                            }
                        }
                    }
                    .modifier(SectionViewModifier())

                    Section {
                        Picker("Mode", selection: $state.scrollingMode) {
                            Text("Accelerated").tag(SchemeState.ScrollingMode.accelerated)
                            Text("By Lines").tag(SchemeState.ScrollingMode.byLines)
                            Text("By Pixels").tag(SchemeState.ScrollingMode.byPixels)
                        }
                        .modifier(PickerViewModifier())

                        switch state.scrollingMode {
                        case .accelerated:
                            Slider(value: $state.scrollingSpeed,
                                   in: 0.0 ... 10.0) {
                                Text("Speed")
                            } minimumValueLabel: {
                                Text("Slower")
                            } maximumValueLabel: {
                                Text("Faster")
                            }

                        case .byLines:
                            Slider(
                                value: $state.linearScrollingLinesInDouble,
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
                                value: $state.linearScrollingPixels,
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
