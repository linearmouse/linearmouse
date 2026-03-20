// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AppPickerSheet: View {
    @Binding var isPresented: Bool
    @State private var selectedApp: AppTarget?
    @State private var showDeleteAlert = false

    @ObservedObject private var schemeState: SchemeState = .shared

    private var shouldShowDeleteButton: Bool {
        selectedApp != nil && schemeState.hasMatchingSchemes(
            forApp: selectedApp,
            forDisplay: schemeState.currentDisplay
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            Form {
                AppPicker(selectedApp: $selectedApp)
            }
            .modifier(FormViewModifier())
            .frame(minHeight: 96)

            HStack(spacing: 8) {
                if shouldShowDeleteButton {
                    Button("Delete…", action: onDelete)
                        .sheetDestructiveActionStyle()
                }
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .sheetSecondaryActionStyle()
                .asCancelAction()
                Button("OK", action: onOK)
                    .sheetPrimaryActionStyle()
                    .asDefaultAction()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(minWidth: 372)
        .onExitCommand {
            isPresented = false
        }
        .onAppear {
            selectedApp = schemeState.currentApp
        }
        .alert(isPresented: $showDeleteAlert) {
            let appName = selectedApp.map { app in
                switch app {
                case let .bundle(bundleIdentifier):
                    return (try? readInstalledApp(bundleIdentifier: bundleIdentifier)?.bundleName) ?? bundleIdentifier
                case let .executable(path):
                    return URL(fileURLWithPath: path).lastPathComponent
                }
            } ?? NSLocalizedString("All Apps", comment: "")

            return Alert(
                title: Text("Delete Configuration?"),
                message: Text("This will delete all settings for \"\(appName)\"."),
                primaryButton: .destructive(Text("Delete")) {
                    confirmDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }

    @MainActor
    private func onOK() {
        isPresented = false
        schemeState.currentApp = selectedApp
    }

    private func onDelete() {
        showDeleteAlert = true
    }

    private func confirmDelete() {
        schemeState.deleteMatchingSchemes(forApp: selectedApp, forDisplay: schemeState.currentDisplay)
        isPresented = false
    }
}
