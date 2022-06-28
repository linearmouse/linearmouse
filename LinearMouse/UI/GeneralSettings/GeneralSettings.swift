// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct GeneralSettings: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        DetailView(showHeader: false) {
            VStack(alignment: .leading, spacing: 20) {
                Section(header: Text("Settings").font(.headline)) {
                    Toggle(isOn: $defaults.showInMenuBar) {
                        VStack(alignment: .leading) {
                            Text("Show in menu bar")
                            Text("""
                            To show the preferences, launch \
                            \(LinearMouse.appName) again.
                            """)
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Section(header: Text("Update").font(.headline)) {
                    CheckForUpdatesView()
                        .controlSize(.small)
                }

                Spacer()

                Section(header: Text("Links").font(.headline)) {
                    VStack(alignment: .leading, spacing: 5) {
                        HyperLink(URL(string: "https://linearmouse.org")!) {
                            Text("Homepage")
                        }
                        HyperLink(URL(string: "https://github.com/linearmouse/linearmouse")!) {
                            Text("GitHub")
                        }
                        HyperLink(URL(string: "https://opencollective.com/linearmouse")!) {
                            Text("Open Collective")
                        }
                        HyperLink(URL(string: "https://github.com/linearmouse/linearmouse/issues")!) {
                            Text("Feedback")
                        }
                        HyperLink(URL(string: "mailto:feedback@linearmouse.org")!) {
                            Text("Contact")
                        }
                        HyperLink(URL(string: "https://ko-fi.com/lujjjh")!) {
                            Image("Kofi")
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }
}

struct GeneralSettings_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettings()
    }
}
