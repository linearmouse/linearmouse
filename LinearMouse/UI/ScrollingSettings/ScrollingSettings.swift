// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

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
                        Picker("", selection: $state.linearScrollingUnit) {
                            ForEach(ScrollingSettingsState.LinearScrollingUnit.allCases) { unit in
                                Text(NSLocalizedString(unit.rawValue, comment: ""))
                            }
                        }
                        .fixedSize()
                        .padding(.trailing)

                        switch state.linearScrollingUnit {
                        case .line:
                            Stepper(
                                value: $state.linearScrollingLines,
                                in: 1 ... 10,
                                step: 1
                            ) {
                                Text(String(state.linearScrollingLines))
                            }

                        case .pixel:
                            Slider(
                                value: $state.linearScrollingPixels,
                                in: 1 ... 128
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
