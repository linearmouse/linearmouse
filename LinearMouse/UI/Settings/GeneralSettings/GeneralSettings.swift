// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct GeneralSettings: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        DetailView(showHeader: false) {
            VStack(alignment: .leading, spacing: 20) {
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

                CheckForUpdatesView()

                HStack {
                    HyperLink(URL(string: "https://linearmouse.org")!) {
                        Text("Homepage")
                    }
                    HyperLink(URL(string: "https://github.com/linearmouse/linearmouse")!) {
                        Text("GitHub")
                    }
                    HyperLink(URL(string: "https://github.com/linearmouse/linearmouse/issues")!) {
                        Text("Feedback")
                    }
                    HyperLink(URL(string: "mailto:feedback@linearmouse.org")!) {
                        Text("Contact")
                    }
                }
                .controlSize(.small)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct GeneralSettings_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettings()
    }
}
