// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct AppPicker: View {
    @ObservedObject var state: AppPickerState = .shared

    @Binding var selectedApp: AppTarget?

    var pickerSelection: Binding<PickerSelection> {
        Binding {
            PickerSelection.value(selectedApp)
        } set: { newValue in
            switch newValue {
            case let .value(value):
                selectedApp = value

            case .other:
                selectedApp = nil

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

                selectedApp = .bundle(installedApp.bundleIdentifier)

            case .otherExecutable:
                selectedApp = nil

                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.allowsOtherFileTypes = true
                panel.message = NSLocalizedString("Select an executable file", comment: "")
                guard panel.runModal() == .OK else {
                    return
                }

                guard let url = panel.url else {
                    return
                }

                selectedApp = .executable(url.path)
            }
        }
    }

    private var isSelectedAppInList: Bool {
        switch selectedApp {
        case .none:
            return true

        case let .bundle(bundleIdentifier):
            return (state.configuredApps + state.installedApps)
                .map(\.bundleIdentifier)
                .contains(bundleIdentifier)

        case let .executable(path):
            return state.configuredExecutables.contains(path)
        }
    }

    var body: some View {
        Picker("Configure for", selection: pickerSelection) {
            Text("All Apps").frame(minHeight: 24).tag(PickerSelection.value(nil))

            Section(header: Text("Configured")) {
                ForEach(state.configuredApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(.bundle(installedApp.bundleIdentifier)))
                }
                ForEach(state.configuredExecutables, id: \.self) { path in
                    HStack(spacing: 8) {
                        if #available(macOS 11.0, *) {
                            Image(systemName: "terminal")
                        }
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                    }
                    .tag(PickerSelection.value(.executable(path)))
                }
            }

            Section(header: Text("Running")) {
                ForEach(state.runningApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(.bundle(installedApp.bundleIdentifier)))
                }
            }

            Section(header: Text("Installed")) {
                ForEach(state.otherApps) { installedApp in
                    AppPickerItem(installedApp: installedApp)
                        .tag(PickerSelection.value(.bundle(installedApp.bundleIdentifier)))
                }
            }

            if !isSelectedAppInList {
                switch selectedApp {
                case .none:
                    EmptyView()

                case let .bundle(bundleIdentifier):
                    if let installedApp = try? readInstalledApp(bundleIdentifier: bundleIdentifier) {
                        AppPickerItem(installedApp: installedApp)
                            .tag(PickerSelection.value(selectedApp))
                    }

                case let .executable(path):
                    HStack(spacing: 8) {
                        if #available(macOS 11.0, *) {
                            Image(systemName: "terminal")
                        }
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                    }
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
    case value(AppTarget?)
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
