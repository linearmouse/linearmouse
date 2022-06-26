// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct WheelSettings: View {
    @StateObject var state = WheelSettingsState()

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

                Toggle(isOn: $state.linearScrollingEnabled) {
                    VStack(alignment: .leading) {
                        Text("Enable linear scrolling")
                        Text("""
                        Disable scrolling acceleration.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                    }
                }
                if state.linearScrollingEnabled {
                    HStack {
                        Text("Scroll")
                        Stepper(
                            value: $state.linearScrollingLines,
                            in: 1 ... 10,
                            step: 1
                        ) {
                            Text(String(state.linearScrollingLines))
                        }
                        Text(state.linearScrollingLines == 1 ? "line" : "lines")
                    }
                    .controlSize(.small)
                    .padding(.leading, 18)
                    .padding(.top, -20)
                }
            }
        }
    }
}
