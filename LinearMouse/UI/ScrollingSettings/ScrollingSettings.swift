// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ScrollingSettings: View {
    @StateObject var state = ScrollingSettingsState()

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    Toggle(isOn: $state.reverseScrollingVertical) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("Reverse scrolling")
                            Text("(vertically)")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $state.reverseScrollingHorizontal) {
                        VStack(alignment: .leading) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("Reverse scrolling")
                                Text("(horizontally)")
                                    .controlSize(.small)
                                    .foregroundColor(.secondary)
                            }
                            Text("""
                            Some gestures, such as swiping back and forward, \
                            may stop working.
                            """)
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $state.linearScrollingVertical) {
                    VStack(alignment: .leading) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("Enable linear scrolling")
                            Text("(vertically)")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        }
                        Text("""
                        Disable scrolling acceleration.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                    }
                }
                if state.linearScrollingVertical {
                    HStack {
                        Picker("", selection: $state.linearScrollingVerticalUnit) {
                            ForEach(ScrollingSettingsState.LinearScrollingUnit.allCases) { unit in
                                Text(NSLocalizedString(unit.rawValue, comment: ""))
                            }
                        }
                        .fixedSize()
                        .padding(.trailing)

                        switch state.linearScrollingVerticalUnit {
                        case .line:
                            Stepper(
                                value: $state.linearScrollingVerticalLines,
                                in: 1 ... 10,
                                step: 1
                            ) {
                                Text(String(state.linearScrollingVerticalLines))
                            }

                        case .pixel:
                            Slider(
                                value: $state.linearScrollingVerticalPixels,
                                in: 1 ... 128
                            )

                            Text(String(state.linearScrollingVerticalPixels))
                                .frame(width: 80)
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, -20)
                    .frame(minHeight: 20)
                }

                Toggle(isOn: $state.linearScrollingHorizontal) {
                    VStack(alignment: .leading) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("Enable linear scrolling")
                            Text("(horizontally)")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        }
                        Text("""
                        Disable scrolling acceleration.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                    }
                }
                if state.linearScrollingHorizontal {
                    HStack {
                        Picker("", selection: $state.linearScrollingHorizontalUnit) {
                            ForEach(ScrollingSettingsState.LinearScrollingUnit.allCases) { unit in
                                Text(NSLocalizedString(unit.rawValue, comment: ""))
                            }
                        }
                        .fixedSize()
                        .padding(.trailing)

                        switch state.linearScrollingHorizontalUnit {
                        case .line:
                            Stepper(
                                value: $state.linearScrollingHorizontalLines,
                                in: 1 ... 10,
                                step: 1
                            ) {
                                Text(String(state.linearScrollingHorizontalLines))
                            }

                        case .pixel:
                            Slider(
                                value: $state.linearScrollingHorizontalPixels,
                                in: 1 ... 128
                            )

                            Text(String(state.linearScrollingHorizontalPixels))
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
