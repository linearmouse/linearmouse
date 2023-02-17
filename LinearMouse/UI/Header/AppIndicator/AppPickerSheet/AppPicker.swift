// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct AppPicker: View {
    @ObservedObject var state: AppPickerState = .shared
    @Binding var selectedApp: String

    var body: some View {
        Picker("Configure for", selection: $selectedApp) {
            Text("All Apps").frame(minHeight: 24).tag("")
            Section(header: Text("Running")) {
                ForEach(state.runningApps) { installedApp in
                    HStack(spacing: 8) {
                        Image(nsImage: installedApp.bundleIcon)
                        Text(installedApp.bundleName)
                            .tag(installedApp.bundleIdentifier)
                    }
                }
            }
            Section(header: Text("Installed")) {
                ForEach(state.installedApps) { installedApp in
                    HStack(spacing: 8) {
                        Image(nsImage: installedApp.bundleIcon)
                        Text(installedApp.bundleName)
                            .tag(installedApp.bundleIdentifier)
                    }
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
