// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct WheelSettings: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    Toggle(isOn: $defaults.reverseScrollingVerticallyOn) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("Reverse scrolling")
                            Text("(vertically)")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $defaults.reverseScrollingHorizontallyOn) {
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

                Toggle(isOn: $defaults.linearScrollingOn) {
                    VStack(alignment: .leading) {
                        Text("Enable linear scrolling")
                        Text("""
                        Disable mouse scrolling acceleration.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("Scroll")
                    Stepper(
                        value: $defaults.scrollLines,
                        in: 1 ... 10,
                        step: 1
                    ) {
                        Text(String(defaults.scrollLines))
                    }
                    Text(defaults.scrollLines == 1 ? "line" : "lines")
                }
                .controlSize(.small)
                .padding(.leading, 18)
                .padding(.top, -20)
                .disabled(!defaults.linearScrollingOn)
            }
        }
    }
}

struct WheelSettings_Previews: PreviewProvider {
    static var previews: some View {
        WheelSettings()
    }
}
