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

                Toggle(isOn: state.reverseScrollingBinding) {
                    Text("Reverse scrolling")
                }

                Toggle(isOn: state.linearScrollingBinding) {
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
                        Picker("", selection: state.linearScrollingUnitBinding) {
                            ForEach(SchemeState.LinearScrollingUnit.allCases) { unit in
                                Text(NSLocalizedString(unit.rawValue, comment: ""))
                            }
                        }
                        .fixedSize()
                        .padding(.trailing)

                        switch state.linearScrollingUnit {
                        case .line:
                            Stepper(
                                value: state.linearScrollingLinesBinding,
                                in: 0 ... 10,
                                step: 1
                            ) {
                                Text(String(state.linearScrollingLines))
                            }

                        case .pixel:
                            Slider(
                                value: state.linearScrollingPixelsBinding,
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
