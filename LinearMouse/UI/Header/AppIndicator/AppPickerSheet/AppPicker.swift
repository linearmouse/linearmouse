// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct AppPicker: View {
    @ObservedObject var state: AppPickerState = .shared
    @Binding var selectedApp: String

    var body: some View {
        Picker("Configure for", selection: $selectedApp) {
            Text("All Apps").frame(minHeight: 24).tag("")
            Section(header: Text("Configured")) {
                ForEach(state.configuredApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                }
            }
            Section(header: Text("Running")) {
                ForEach(state.runningApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                }
            }
            Section(header: Text("Installed")) {
                ForEach(state.otherApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                state.refreshInstalledApps()
            }
        }
    }
}

struct AppPickerItem: View {
    var installedApp: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: installedApp.bundleIcon)
            Text(installedApp.bundleName)
                .tag(installedApp.bundleIdentifier)
        }
    }
}
