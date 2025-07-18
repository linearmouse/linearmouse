// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Defaults
import LaunchAtLogin
import SwiftUI

struct GeneralSettings: View {
    @Default(.showInMenuBar) var showInMenuBar
    @Default(.showInDock) var showInDock
    @Default(.bypassEventsFromOtherApplications) var bypassEventsFromOtherApplications

    var body: some View {
        DetailView(schemeSpecific: false) {
            Form {
                Section {
                    Toggle(isOn: $showInMenuBar.animation()) {
                        withDescription {
                            Text("Show in menu bar")
                            if !showInMenuBar {
                                Text("To show the settings, launch \(LinearMouse.appName) again.")
                            }
                        }
                    }

                    LaunchAtLogin.Toggle {
                        Text("Start at login")
                    }

                    Toggle(isOn: $showInDock) {
                        Text("Show in Dock")
                    }

                    Toggle(isOn: $bypassEventsFromOtherApplications) {
                        withDescription {
                            Text("Bypass events from other applications")
                            Text(
                                "If enabled, \(LinearMouse.appName) will not modify events sent by other applications, such as Logi Options+."
                            )
                        }
                    }
                }
                .modifier(SectionViewModifier())

                ConfigurationSection()

                Section {
                    CheckForUpdatesView()
                }
                .modifier(SectionViewModifier())

                LoggingSection()

                Section {
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
                .modifier(SectionViewModifier())
                .frame(minHeight: 22)
            }
            .modifier(FormViewModifier())
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
