// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct AppPicker: View {
    @ObservedObject var state: AppPickerState = .shared

    @Binding var selectedApp: String

    var pickerSelection: Binding<PickerSelection> {
        Binding {
            PickerSelection.value(selectedApp)
        } set: { newValue in
            print("newValue \(newValue)")
            switch newValue {
            case let .value(value):
                selectedApp = value
            case .other:
                selectedApp = ""

                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                if #available(macOS 11.0, *) {
                    panel.allowedContentTypes = [.applicationBundle]
                }
                guard panel.runModal() == .OK else {
                    return
                }

                guard let url = panel.url else {
                    return
                }

                guard let installedApp = try? readInstalledApp(at: url) else {
                    return
                }

                selectedApp = installedApp.bundleIdentifier
            }
        }
    }

    private var isSelectedAppInList: Bool {
        (
            [""] +
                (state.configuredApps + state.installedApps)
                .map(\.bundleIdentifier)
        )
        .contains(selectedApp)
    }

    var body: some View {
        Picker("Configure for", selection: pickerSelection) {
            Text("All Apps").frame(minHeight: 24).tag(PickerSelection.value(""))

            Section(header: Text("Configured")) {
                ForEach(state.configuredApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(installedApp.bundleIdentifier))
                }
            }

            Section(header: Text("Running")) {
                ForEach(state.runningApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(installedApp.bundleIdentifier))
                }
            }

            Section(header: Text("Installed")) {
                ForEach(state.otherApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(installedApp.bundleIdentifier))
                }
            }

            if !isSelectedAppInList {
                if let installedApp = try? readInstalledApp(bundleIdentifier: selectedApp) {
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(selectedApp))
                } else {
                    Text(selectedApp)
                        .tag(PickerSelection.value(selectedApp))
                }
            }

            Text("Other…").tag(PickerSelection.other)
        }
        .onAppear {
            DispatchQueue.main.async {
                state.refreshInstalledApps()
            }
        }
    }
}

enum PickerSelection: Hashable {
    case value(String)
    case other
}

struct AppPickerItem: View {
    var installedApp: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: installedApp.bundleIcon)
            Text(installedApp.bundleName)
        }
    }
}
