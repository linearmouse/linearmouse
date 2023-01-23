// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ScrollingSettings: View {
    @ObservedObject var state = State.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 20) {
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

                Toggle(isOn: $state.reverseScrolling) {
                    VStack(alignment: .leading) {
                        Text("Reverse scrolling")
                        if state.orientation == .horizontal {
                            Text("Some gestures, such as swiping back and forward, may stop working.")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Picker("Mode", selection: $state.scrollingMode) {
                    Text("Accelerated").tag(SchemeState.ScrollingMode.accelerated)
                    Text("Linear").tag(SchemeState.ScrollingMode.linear)
                }
                .fixedSize()

                if state.scrollingMode == .accelerated {
                    Slider(value: $state.scrollingSpeed,
                           in: 0.0 ... 10.0) {
                        Text("Speed")
                    }
                }

                if state.scrollingMode == .linear {
                    HStack {
                        Picker("Unit", selection: $state.linearScrollingUnit) {
                            Text("Lines").tag(SchemeState.LinearScrollingUnit.line)
                            Text("Pixels").tag(SchemeState.LinearScrollingUnit.pixel)
                        }
                        .fixedSize()
                        .padding(.trailing)

                        switch state.linearScrollingUnit {
                        case .line:
                            Slider(
                                value: $state.linearScrollingLinesInDouble,
                                in: 0 ... 10,
                                step: 1
                            )

                            Text(String(state.linearScrollingLines))
                                .frame(width: 80)

                        case .pixel:
                            Slider(
                                value: $state.linearScrollingPixels,
                                in: 0 ... 128
                            )

                            Text(String(state.linearScrollingPixels))
                                .frame(width: 80)
                        }
                    }
                }
            }
        }
    }
}
