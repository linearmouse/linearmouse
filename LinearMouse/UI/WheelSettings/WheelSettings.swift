// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct WheelSettings: View {
    @ObservedObject var configurationState = ConfigurationState()

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    if let index = configurationState.activeDeviceSpecificSchemeIndex {
                        let scheme = $configurationState.configuration.schemes[index]

                        Toggle(isOn: Binding<Bool>(
                            get: {
                                scheme.scrolling.wrappedValue?.reverse?.vertical ?? false
                            },
                            set: {
                                var scrolling = Scheme.Scrolling()
                                scrolling.reverse = Scheme.Scrolling.Reverse(vertical: $0)
                                scrolling.merge(into: &scheme.scrolling.wrappedValue)
                            }
                        )) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("Reverse scrolling")
                                Text("(vertically)")
                                    .controlSize(.small)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

//                VStack(alignment: .leading) {
//                    Toggle(isOn: $defaults.reverseScrollingHorizontallyOn) {
//                        VStack(alignment: .leading) {
//                            HStack(alignment: .firstTextBaseline, spacing: 2) {
//                                Text("Reverse scrolling")
//                                Text("(horizontally)")
//                                    .controlSize(.small)
//                                    .foregroundColor(.secondary)
//                            }
//                            Text("""
//                            Some gestures, such as swiping back and forward, \
//                            may stop working.
//                            """)
//                            .controlSize(.small)
//                            .foregroundColor(.secondary)
//                        }
//                    }
//                }
//
//                Toggle(isOn: $defaults.linearScrollingOn) {
//                    VStack(alignment: .leading) {
//                        Text("Enable linear scrolling")
//                        Text("""
//                        Disable mouse scrolling acceleration.
//                        """)
//                        .controlSize(.small)
//                        .foregroundColor(.secondary)
//                    }
//                }
//                HStack {
//                    Text("Scroll")
//                    Stepper(
//                        value: $defaults.scrollLines,
//                        in: 1 ... 10,
//                        step: 1
//                    ) {
//                        Text(String(defaults.scrollLines))
//                    }
//                    Text(defaults.scrollLines == 1 ? "line" : "lines")
//                }
//                .controlSize(.small)
//                .padding(.leading, 18)
//                .padding(.top, -20)
//                .disabled(!defaults.linearScrollingOn)
            }
        }
    }
}
