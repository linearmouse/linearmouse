// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Defaults
import SwiftUI

struct GeneralSettings: View {
    @Default(.showInMenuBar) var showInMenuBar

    var body: some View {
        DetailView(schemeSpecific: false) {
            VStack(alignment: .leading, spacing: 20) {
                Section(header: Text("Settings").font(.headline)) {
                    Toggle(isOn: $showInMenuBar) {
                        VStack(alignment: .leading) {
                            Text("Show in menu bar")
                            Text("""
                            To show the settings, launch \
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
                }

                Spacer()

                Section(header: Text("Links").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HyperLink(URLs.homepage) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("🏡")
                                Text("Homepage")
                            }
                        }
                        HyperLink(URLs.bugReport) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("🐛")
                                Text("Bug report")
                            }
                        }
                        HyperLink(URLs.featureRequest) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("✍🏻")
                                Text("Feature request")
                            }
                        }
                        HyperLink(URLs.donate) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("❤️")
                                Text("Donate")
                            }
                        }
                    }
                }
            }
        }
    }
}

extension GeneralSettings {
    enum URLs {
        static func withEnvironmentParametersAppended(for url: URL) -> URL {
            var osVersion = Foundation.ProcessInfo.processInfo.operatingSystemVersionString
            if osVersion.hasPrefix("Version ") {
                osVersion = String(osVersion.dropFirst("Version ".count))
            }
            osVersion = "macOS \(osVersion)"
            let linearMouseVersion = "v\(LinearMouse.appVersion)"

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            var queryItems = components.queryItems ?? []
            queryItems.append(contentsOf: [
                .init(name: "os", value: osVersion),
                .init(name: "linearmouse", value: linearMouseVersion)
            ])
            components.queryItems = queryItems

            return components.url!
        }

        static var homepage: URL {
            URL(string: "https://linearmouse.app")!
        }

        static var bugReport: URL {
            withEnvironmentParametersAppended(for: URL(string: "https://go.linearmouse.app/bug-report")!)
        }

        static var featureRequest: URL {
            withEnvironmentParametersAppended(for: URL(string: "https://go.linearmouse.app/feature-request")!)
        }

        static var donate: URL {
            URL(string: "https://go.linearmouse.app/donate")!
        }
    }
}
