//
//  GeneralView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/7/30.
//

import SwiftUI

struct GeneralView: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: $defaults.reverseScrollingOn) {
                VStack(alignment: .leading) {
                    Text("Reverse scrolling")
                    Text("""
                        Reverse the scroll direction for a mouse \
                        but won't reverse the scroll direction \
                        for a Trackpad.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading) {
                Toggle(isOn: $defaults.linearScrollingOn) {
                    VStack(alignment: .leading) {
                        Text("Enable linear scrolling")
                        Text("""
                            Disable mouse scrolling acceleration.
                            """)
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Stepper(
                    value: $defaults.scrollLines,
                    in: 1...10,
                    step: 1) {
                    Text("Scroll")
                    Text(String(defaults.scrollLines))
                    Text(defaults.scrollLines == 1 ? "line" : "lines")
                }
                .controlSize(.small)
                .padding(.leading, 18)
                .disabled(!defaults.linearScrollingOn)
            }

            Toggle(isOn: $defaults.universalBackForwardOn) {
                VStack(alignment: .leading) {
                    Text("Enable universal back and forward")
                    Text("""
                        Convert the back and forward side buttons to \
                        swiping gestures to allow universal back and \
                        forward functionality.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: $defaults.showInMenuBar) {
                VStack(alignment: .leading) {
                    Text("Show in menu bar")
                    Text("""
                        To show the preferences, launch \
                        \(LinearMouse.appName) again.
                        """)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(alignment: .leading) {
                Text("Version: \(LinearMouse.appVersion)")

                HStack {
                    HyperLink(URL(string: "https://linearmouse.lujjjh.com/")!) {
                        Text("Homepage")
                    }
                    HyperLink(URL(string: "https://github.com/lujjjh/LinearMouse")!) {
                        Text("GitHub")
                    }
                    HyperLink(URL(string: "https://github.com/lujjjh/LinearMouse/discussions/new")!) {
                        Text("Feedback")
                    }
                }
            }
            .controlSize(.small)
            .foregroundColor(.secondary)
        }
        .frame(minWidth: 0, maxWidth: .infinity,
               minHeight: 0, maxHeight: .infinity,
               alignment: .topLeading)
    }
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
