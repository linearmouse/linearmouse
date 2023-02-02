// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ScrollingSettings: View {
    @State private var direction: Scheme.Scrolling.Direction = .vertical
    @ObservedObject private var schemeState: SchemeState = .shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()

                    Picker("", selection: $direction) {
                        Text("Vertical").tag(Scheme.Scrolling.Direction.vertical)
                        Text("Horizontal").tag(Scheme.Scrolling.Direction.horizontal)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    Spacer()
                }
                .padding(.top, 20)

                Form {
                    Section {
                        Toggle(isOn: $schemeState.scheme.scrolling
                            .optionalBinding(\.reverse)
                            .optionalBinding(direction: direction)
                            .withDefault(false)) {
                                withDescription {
                                    Text("Reverse scrolling")
                                    if direction == .horizontal {
                                        Text("Some gestures, such as swiping back and forward, may stop working.")
                                    }
                                }
                            }
                    }
                    .modifier(SectionViewModifier())

                    Section {
                        Picker("Mode", selection: scrollingModeBinding) {
                            Text("Accelerated").tag(ScrollingMode.accelerated)
                            Text("By Lines").tag(ScrollingMode.byLines)
                            Text("By Pixels").tag(ScrollingMode.byPixels)
                        }
                        .modifier(PickerViewModifier())
                    }
                    .modifier(SectionViewModifier())

                    //                Form {
                    //                    Section {
                    //                        Picker("Mode", selection: $state.scrollingMode) {
                    //                            Text("Accelerated").tag(SchemeState.ScrollingMode.accelerated)
                    //                            Text("By Lines").tag(SchemeState.ScrollingMode.byLines)
                    //                            Text("By Pixels").tag(SchemeState.ScrollingMode.byPixels)
                    //                        }
                    //                        .modifier(PickerViewModifier())
                    //
                    //                        switch state.scrollingMode {
                    //                        case .accelerated:
                    //                            Slider(value: $state.scrollingSpeed,
                    //                                   in: 0.0 ... 10.0) {
                    //                                Text("Speed")
                    //                            } minimumValueLabel: {
                    //                                Text("Slower")
                    //                            } maximumValueLabel: {
                    //                                Text("Faster")
                    //                            }
                    //
                    //                        case .byLines:
                    //                            Slider(
                    //                                value: $state.linearScrollingLinesInDouble,
                    //                                in: 0 ... 10,
                    //                                step: 1
                    //                            ) {
                    //                                Text("Distance")
                    //                            } minimumValueLabel: {
                    //                                Text("0")
                    //                            } maximumValueLabel: {
                    //                                Text("10")
                    //                            }
                    //
                    //                        case .byPixels:
                    //                            Slider(
                    //                                value: $state.linearScrollingPixels,
                    //                                in: 0 ... 128
                    //                            ) {
                    //                                Text("Distance")
                    //                            } minimumValueLabel: {
                    //                                Text("0px")
                    //                            } maximumValueLabel: {
                    //                                Text("128px")
                    //                            }
                    //                        }
                    //                    }
                    //                    .modifier(SectionViewModifier())
                }
                .modifier(FormViewModifier())
            }
        }
    }
}

extension ScrollingSettings {
    enum ScrollingMode {
        case accelerated, byLines, byPixels
    }

    var scrollingModeBinding: Binding<ScrollingMode> {
        $schemeState.scheme.scrolling
            .optionalBinding(\.distance)
            .optionalBinding(direction: direction)
            .withDefault(.auto)
            .map(get: {
                switch $0 {
                case .auto:
                    return .accelerated
                case .line:
                    return .byLines
                case .pixel:
                    return .byPixels
                }
            }, set: {
                switch $0 {
                case .accelerated:
                    return .auto
                case .byLines:
                    return .line(3)
                case .byPixels:
                    return .pixel(36)
                }
            })
    }
}
