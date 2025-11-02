// MIT License
// Copyright (c) 2021-2025 LinearMouse

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
            case .otherExecutable:
                selectedApp = ""

                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.allowsOtherFileTypes = true
                panel.message = "Select an executable file"
                guard panel.runModal() == .OK else {
                    return
                }

                guard let url = panel.url else {
                    return
                }

                selectedApp = "executable:\(url.path)"
            }
        }
    }

    private var isSelectedAppInList: Bool {
        let appIdentifiers = [""] +
            (state.configuredApps + state.installedApps)
            .map(\.bundleIdentifier)

        let executableIdentifiers = state.configuredExecutables
            .map { "executable:\($0)" }

        return (appIdentifiers + executableIdentifiers).contains(selectedApp)
    }

    var body: some View {
        Picker("Configure for", selection: pickerSelection) {
            Text("All Apps").frame(minHeight: 24).tag(PickerSelection.value(""))

            Section(header: Text("Configured")) {
                ForEach(state.configuredApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(installedApp.bundleIdentifier))
                }
                ForEach(state.configuredExecutables, id: \.self) { path in
                    HStack(spacing: 8) {
                        if #available(macOS 11.0, *) {
                            Image(systemName: "terminal")
                        }
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                    }
                    .tag(PickerSelection.value("executable:\(path)"))
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
                if selectedApp.hasPrefix("executable:") {
                    let path = String(selectedApp.dropFirst("executable:".count))
                    HStack(spacing: 8) {
                        if #available(macOS 11.0, *) {
                            Image(systemName: "terminal")
                        }
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                    }
                    .tag(PickerSelection.value(selectedApp))
                } else if let installedApp = try? readInstalledApp(bundleIdentifier: selectedApp) {
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(selectedApp))
                } else {
                    Text(selectedApp)
                        .tag(PickerSelection.value(selectedApp))
                }
            }

            Text("Other App…").tag(PickerSelection.other)
            Text("Other Executable…").tag(PickerSelection.otherExecutable)
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
    case otherExecutable
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
