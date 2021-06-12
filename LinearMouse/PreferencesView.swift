//
//  PreferencesView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import SwiftUI
import AppStorage

struct PreferencesView: View {
    @StateObject var defaults = AppDefaults.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Version: \(LinearMouse.appVersion)")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()

            Toggle(isOn: $defaults.reverseScrollingOn) {
                VStack(alignment: .leading) {
                    Text("Reverse scrolling")
                    Text("""
                        Reverse the scroll direction for a mouse \
                        but won't reverse the scroll direction \
                        for a Trackpad.
                        """)
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
                    Text(defaults.scrollLines == 1
                            ? "line"
                            : "lines")
                }
                .padding(.leading, 18)
                .disabled(!defaults.linearScrollingOn)
            }

            Spacer()

            HStack {
                HyperLink(URL(string: "https://linearmouse.lujjjh.com/")!) {
                    Text("Website")
                }
                HyperLink(URL(string: "https://github.com/lujjjh/LinearMouse")!) {
                    Text("GitHub")
                }
                HyperLink(URL(string: "https://github.com/lujjjh/LinearMouse/discussions/new")!) {
                    Text("Feedback")
                }
            }
        }
        .padding(.all, 30)
        .frame(width: 400, height: 300)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
