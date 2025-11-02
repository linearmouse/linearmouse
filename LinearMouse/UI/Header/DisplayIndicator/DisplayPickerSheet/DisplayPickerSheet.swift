// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct DisplayPickerSheet: View {
    @Binding var isPresented: Bool
    @State private var selectedDisplay = ""
    @State private var showDeleteAlert = false

    @ObservedObject private var schemeState: SchemeState = .shared

    private var shouldShowDeleteButton: Bool {
        // Only show if a display is selected and there are matching schemes
        let display = selectedDisplay.isEmpty ? nil : selectedDisplay
        return !selectedDisplay.isEmpty && schemeState.hasMatchingSchemes(
            forApp: schemeState.currentApp,
            forDisplay: display
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            Form {
                DisplayPicker(selectedDisplay: $selectedDisplay)
            }
            .modifier(FormViewModifier())

            HStack {
                if shouldShowDeleteButton {
                    Button("Delete…", action: onDelete)
                        .foregroundColor(.red)
                }
                Spacer()
                Button("OK", action: onOK)
            }
            .padding()
        }
        .frame(minWidth: 300)
        .onAppear {
            selectedDisplay = schemeState.currentDisplay ?? ""
        }
        .alert(isPresented: $showDeleteAlert) {
            let displayName = selectedDisplay.isEmpty ? "All Displays" : selectedDisplay

            return Alert(
                title: Text("Delete Configuration?"),
                message: Text("This will delete all settings for \"\(displayName)\"."),
                primaryButton: .destructive(Text("Delete")) {
                    confirmDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func onOK() {
        isPresented = false
        DispatchQueue.main.async {
            schemeState.currentDisplay = selectedDisplay == "" ? nil : selectedDisplay
        }
    }

    private func onDelete() {
        showDeleteAlert = true
    }

    private func confirmDelete() {
        let display = selectedDisplay.isEmpty ? nil : selectedDisplay
        schemeState.deleteMatchingSchemes(forApp: schemeState.currentApp, forDisplay: display)
        isPresented = false
    }
}
