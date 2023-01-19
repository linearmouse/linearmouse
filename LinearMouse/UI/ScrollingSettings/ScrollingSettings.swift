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

                Toggle(isOn: $state.linearScrolling) {
                    VStack(alignment: .leading) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("Enable linear scrolling")
                        }
                        Text("""
                        Disable scrolling acceleration.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                    }
                }
                if state.linearScrolling {
                    HStack {
                        Picker("", selection: $state.linearScrollingUnit) {
                            ForEach(SchemeState.LinearScrollingUnit.allCases) { unit in
                                Text(NSLocalizedString(unit.rawValue, comment: ""))
                            }
                        }
                        .fixedSize()
                        .padding(.trailing)

                        switch state.linearScrollingUnit {
                        case .line:
                            Stepper(
                                value: $state.linearScrollingLines,
                                in: 0 ... 10,
                                step: 1
                            ) {
                                Text(String(state.linearScrollingLines))
                            }

                        case .pixel:
                            Slider(
                                value: $state.linearScrollingPixels,
                                in: 0 ... 128
                            )

                            Text(String(state.linearScrollingPixels))
                                .frame(width: 80)
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, -20)
                    .frame(minHeight: 20)
                }
            }
        }
    }
}
