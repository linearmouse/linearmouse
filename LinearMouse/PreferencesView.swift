//
//  PreferencesView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var defaults = AppDefaults.shared
    @State var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading) {
            TabView(selection: $selectedTab) {
                VStack (alignment: .leading, spacing: 20) {
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
                            Text(defaults.scrollLines == 1 ? "line" : "lines")
                        }
                        .padding(.leading, 18)
                        .disabled(!defaults.linearScrollingOn)
                    }

                    Toggle(isOn: $defaults.linearMovementOn) {
                        VStack(alignment: .leading) {
                            Text("Enable linear movement")
                            Text("""
                                Disable cursor acceleration.
                                """)
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
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
                .tabItem { Text("General") }
                .tag(0)

                Form {
                    ModifierKeyActionPicker(label: "⌘ (Command)", action: $defaults.modifiersCommandAction)
                    ModifierKeyActionPicker(label: "⇧ (Shift)", action: $defaults.modifiersShiftAction)
                    ModifierKeyActionPicker(label: "⌥ (Option)", action: $defaults.modifiersAlternateAction)
                    ModifierKeyActionPicker(label: "⌃ (Control)", action: $defaults.modifiersControlAction)
                }
                .padding()
                .tabItem { Text("Modifier Keys") }
                .tag(1)

                VStack(spacing: 20) {
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
                .padding()
                .tabItem { Text("About") }
                .tag(2)
            }
        }
        .padding()
        .frame(width: 400, height: 450)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView(selectedTab: 2)
    }
}
